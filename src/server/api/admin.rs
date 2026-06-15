// SPDX-License-Identifier: MIT

use crate::prelude::*;

use axum::Form;
use axum::response::IntoResponse;
use axum::{Extension, Json, extract::Path};

use crate::server::{ServerContext, main::SessionExtractor};
use crate::sqlite::configdb::{FilterEntry, FilterRow};

pub(super) async fn update_ja4db(
    Extension(context): Extension<Arc<ServerContext>>,
    _session: SessionExtractor,
) -> Result<Json<serde_json::Value>, AppError> {
    info!("API request to update JA4 database");
    match do_update(context).await {
        Ok(response) => {
            info!("JA4db updated");
            Ok(response)
        }
        Err(err) => {
            error!("Request to update JA4db failed: {err}");
            Err(err.into())
        }
    }
}

async fn do_update(context: Arc<ServerContext>) -> Result<Json<serde_json::Value>> {
    let mut conn = context.configdb.pool.begin().await?;
    let n = crate::commands::ja4db::updatedb(&mut conn).await?;
    conn.commit().await?;
    let response = json!({
        "entries": n,
    });
    Ok(Json(response))
}

/// Add auto-archive filters, but to be extended.
///
/// For now just use the FilterEntry from configdb as the form
/// type. But that may need to change as we extend this.
pub(super) async fn add_filter(
    _session: SessionExtractor,
    Extension(context): Extension<Arc<ServerContext>>,
    Form(mut entry): Form<FilterEntry>,
) -> Result<impl IntoResponse, AppError> {
    let comment = entry.comment.take();
    let mut tx = context.configdb.pool.begin().await?;

    let key = format!(
        "{},{},{},{}",
        entry.sensor.as_ref().map_or("*", |v| v),
        &entry.src_ip.as_ref().map_or("*", |v| v),
        &entry.dest_ip.as_ref().map_or("*", |v| v),
        entry.signature_id
    );

    if let Ok(filters) = context.auto_archive.read() {
        if filters.has_key(&key) {
            info!("Arhive filters already contains key {}", &key);
            return Ok(Json(json!({})));
        }
    }

    let sql = "INSERT INTO filters (user_id, filter, comment) VALUES (?, ?, ?)";
    sqlx::query(sql)
        .bind(0)
        .bind(serde_json::to_value(&entry).unwrap())
        .bind(&comment)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    let mut ingest = context.auto_archive.write().unwrap();
    ingest.add(&entry);

    info!(
        "New auto-archive filter added {:?} with comment: {:?}",
        &entry, &comment
    );

    Ok(Json(json!({})))
}

pub(super) async fn get_filters(
    _sesssion: SessionExtractor,
    Extension(context): Extension<Arc<ServerContext>>,
) -> Result<impl IntoResponse, AppError> {
    let rows = context.configdb.get_filters().await?;
    Ok(Json(rows))
}

pub(super) async fn delete_filter(
    _session: SessionExtractor,
    Extension(context): Extension<Arc<ServerContext>>,
    Path(id): Path<u32>,
) -> Result<impl IntoResponse, AppError> {
    // Remove from database.
    let mut tx = context.configdb.pool.begin().await?;
    let row: Option<FilterRow> =
        sqlx::query_as::<_, FilterRow>("SELECT * FROM filters WHERE id = ?")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?;
    match row {
        Some(row) => {
            sqlx::query("DELETE FROM filters WHERE id = ?")
                .bind(id)
                .execute(&mut *tx)
                .await?;
            tx.commit().await?;

            // Remove from current ingest processing.
            let mut ingest = context.auto_archive.write().unwrap();
            ingest.remove(&row.filter.0);
        }
        None => {
            return Err(AppError::BadRequest("filter not found".to_string()));
        }
    }

    Ok(Json(json!({})))
}

pub(super) async fn kv_get_config(
    _sesssion: SessionExtractor,
    Extension(context): Extension<Arc<ServerContext>>,
) -> Result<impl IntoResponse, AppError> {
    let rows = context.configdb.kv_get_config().await?;
    Ok(Json(rows))
}

pub(super) async fn kv_set_config(
    _sesssion: SessionExtractor,
    Extension(context): Extension<Arc<ServerContext>>,
    Path(key): Path<String>,
    Json(value): Json<serde_json::Value>,
) -> Result<impl IntoResponse, AppError> {
    context.configdb.kv_set_config(&key, &value).await?;
    Ok(())
}

// ====== User Management ======

use serde::Deserialize;

#[derive(Deserialize, Debug)]
pub(super) struct CreateUserRequest {
    pub username: String,
    pub password: String,
    #[serde(default = "default_role")]
    pub role: String,
}

fn default_role() -> String {
    "user".to_string()
}

#[derive(Deserialize, Debug)]
pub(super) struct ResetPasswordRequest {
    pub password: String,
}

async fn require_admin(_context: &Arc<ServerContext>, session: &crate::server::session::Session) -> Result<(), AppError> {
    // Check session.role first — it's already loaded when the session was created
    if let Some(role) = &session.role {
        if role == "admin" {
            return Ok(());
        }
        return Err(AppError::BadRequest("admin role required".to_string()));
    }
    // Fallback: no role on session (shouldn't happen for logged-in users)
    if session.username.is_some() {
        warn!("Session has username but no role set");
    }
    Err(AppError::BadRequest("admin role required".to_string()))
}

/// GET /api/admin/users — list all users
pub(super) async fn get_users(
    session: SessionExtractor,
    Extension(context): Extension<Arc<ServerContext>>,
) -> Result<impl IntoResponse, AppError> {
    require_admin(&context, &session.0).await?;
    let users = context.configdb.get_users().await?;
    Ok(Json(users))
}

/// POST /api/admin/users — create a new user
pub(super) async fn create_user(
    session: SessionExtractor,
    Extension(context): Extension<Arc<ServerContext>>,
    Json(req): Json<CreateUserRequest>,
) -> Result<impl IntoResponse, AppError> {
    info!("create_user: username={}, role={}, session.username={:?}, session.role={:?}",
        req.username, req.role, session.0.username, session.0.role);
    require_admin(&context, &session.0).await?;

    if req.username.trim().is_empty() {
        return Err(AppError::BadRequest("username is required".to_string()));
    }
    if req.password.len() < 4 {
        return Err(AppError::BadRequest("password must be at least 4 characters".to_string()));
    }
    if req.role != "admin" && req.role != "user" {
        return Err(AppError::BadRequest("role must be 'admin' or 'user'".to_string()));
    }

    let user_id = context
        .configdb
        .create_user(&req.username.trim(), &req.password, &req.role)
        .await
        .map_err(|err| {
            error!("Failed to create user: {:?}", err);
            AppError::BadRequest(format!("failed to create user: {}", err))
        })?;

    info!("Admin created user: username={}, role={}", req.username, &req.role);
    Ok(Json(json!({
        "uuid": user_id,
        "username": req.username.trim(),
        "role": req.role,
    })))
}

/// DELETE /api/admin/users/{id} — delete a user
pub(super) async fn delete_user(
    session: SessionExtractor,
    Extension(context): Extension<Arc<ServerContext>>,
    Path(user_id): Path<String>,
) -> Result<impl IntoResponse, AppError> {
    require_admin(&context, &session.0).await?;

    let n = context.configdb.delete_user_by_uuid(&user_id).await?;
    if n == 0 {
        return Err(AppError::BadRequest("user not found".to_string()));
    }

    info!("Admin deleted user: uuid={}", &user_id);
    Ok(Json(json!({
        "deleted": true,
    })))
}

/// POST /api/admin/users/{id}/password — reset user password
pub(super) async fn reset_user_password(
    session: SessionExtractor,
    Extension(context): Extension<Arc<ServerContext>>,
    Path(user_id): Path<String>,
    Json(req): Json<ResetPasswordRequest>,
) -> Result<impl IntoResponse, AppError> {
    require_admin(&context, &session.0).await?;

    if req.password.len() < 4 {
        return Err(AppError::BadRequest("password must be at least 4 characters".to_string()));
    }

    let ok = context
        .configdb
        .reset_user_password(&user_id, &req.password)
        .await?;
    if !ok {
        return Err(AppError::BadRequest("user not found".to_string()));
    }

    info!("Admin reset password for user: uuid={}", &user_id);
    Ok(Json(json!({
        "password_reset": true,
    })))
}
