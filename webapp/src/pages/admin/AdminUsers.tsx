// SPDX-FileCopyrightText: (C) 2026
// SPDX-License-Identifier: MIT

import { createSignal, onMount } from "solid-js";
import { Container, Table, Button, Form, Modal, Alert } from "solid-bootstrap";
import { Top } from "../../Top";

interface User {
  uuid: string;
  username: string;
  role: string;
}

export function AdminUsers() {
  const [users, setUsers] = createSignal<User[]>([]);
  const [loading, setLoading] = createSignal(true);
  const [error, setError] = createSignal("");
  const [success, setSuccess] = createSignal("");

  const [showCreate, setShowCreate] = createSignal(false);
  const [newUsername, setNewUsername] = createSignal("");
  const [newPassword, setNewPassword] = createSignal("");
  const [newRole, setNewRole] = createSignal("user");
  const [submitting, setSubmitting] = createSignal(false);

  const [showResetPwd, setShowResetPwd] = createSignal(false);
  const [resetUserId, setResetUserId] = createSignal("");
  const [resetUsername, setResetUsername] = createSignal("");
  const [resetPassword, setResetPassword] = createSignal("");
  const [resettingPwd, setResettingPwd] = createSignal(false);

  const fetchUsers = async () => {
    setLoading(true);
    setError("");
    try {
      const response = await fetch("/api/admin/users");
      if (!response.ok) {
        const err = await response.json();
        throw new Error(err.error || "Failed to fetch users");
      }
      const data = await response.json();
      setUsers(data);
    } catch (e: any) {
      setError(e.message || "Failed to load users");
    } finally {
      setLoading(false);
    }
  };

  const handleCreateUser = async () => {
    setError("");
    setSuccess("");

    if (!newUsername().trim()) {
      setError("Username is required");
      return;
    }
    if (!newPassword()) {
      setError("Password is required");
      return;
    }
    if (newPassword().length < 4) {
      setError("Password must be at least 4 characters");
      return;
    }

    setSubmitting(true);
    try {
      const response = await fetch("/api/admin/users", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          username: newUsername().trim(),
          password: newPassword(),
          role: newRole(),
        }),
      });
      if (!response.ok) {
        const err = await response.json();
        throw new Error(err.error || "Failed to create user");
      }
      setSuccess(`User "${newUsername()}" created`);
      setNewUsername("");
      setNewPassword("");
      setNewRole("user");
      setShowCreate(false);
      fetchUsers();
    } catch (e: any) {
      console.error("Create user failed:", e);
      if (e instanceof TypeError && e.message === "Failed to fetch") {
        setError("Cannot connect to server. Make sure the backend is running on port 5636.");
      } else {
        setError(e.message || "Failed to create user");
      }
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteUser = async (user: User) => {
    if (!confirm(`Delete user "${user.username}"? This cannot be undone.`)) return;
    setError("");
    try {
      const response = await fetch(`/api/admin/users/${user.uuid}`, {
        method: "DELETE",
      });
      if (!response.ok) {
        const err = await response.json();
        throw new Error(err.error || "Failed to delete user");
      }
      setSuccess(`User "${user.username}" deleted`);
      fetchUsers();
    } catch (e: any) {
      setError(e.message || "Failed to delete user");
    }
  };

  const openResetPassword = (user: User) => {
    setResetUserId(user.uuid);
    setResetUsername(user.username);
    setResetPassword("");
    setShowResetPwd(true);
  };

  const handleResetPassword = async () => {
    setError("");
    setSuccess("");

    if (!resetPassword()) {
      setError("Password is required");
      return;
    }
    if (resetPassword().length < 4) {
      setError("Password must be at least 4 characters");
      return;
    }

    setResettingPwd(true);
    try {
      const response = await fetch(`/api/admin/users/${resetUserId()}/password`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password: resetPassword() }),
      });
      if (!response.ok) {
        const err = await response.json();
        throw new Error(err.error || "Failed to reset password");
      }
      setSuccess(`Password reset for "${resetUsername()}"`);
      setShowResetPwd(false);
    } catch (e: any) {
      setError(e.message || "Failed to reset password");
    } finally {
      setResettingPwd(false);
    }
  };

  onMount(() => {
    fetchUsers();
  });

  return (
    <>
      <Top />
      <Container class={"mt-3"}>
        <h4>User Management</h4>

        {error() && (
          <Alert variant="danger" dismissible onclose={() => setError("")}>
            {error()}
          </Alert>
        )}
        {success() && (
          <Alert variant="success" dismissible onclose={() => setSuccess("")}>
            {success()}
          </Alert>
        )}

        <div class="mb-3">
          <Button onclick={() => setShowCreate(true)}>Create User</Button>
        </div>

        {loading() ? (
          <p>Loading...</p>
        ) : (
          <Table striped bordered hover>
            <thead>
              <tr>
                <th>Username</th>
                <th>Role</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {users().length === 0 ? (
                <tr>
                  <td colSpan="3" class="text-center">No users found</td>
                </tr>
              ) : (
                users().map((user) => (
                  <tr>
                    <td>{user.username}</td>
                    <td>
                      <span
                        class={`badge bg-${user.role === "admin" ? "danger" : "primary"}`}
                      >
                        {user.role}
                      </span>
                    </td>
                    <td>
                      <Button
                        variant="warning"
                        size="sm"
                        class="me-2"
                        onclick={() => openResetPassword(user)}
                      >
                        Reset Password
                      </Button>
                      <Button
                        variant="danger"
                        size="sm"
                        onclick={() => handleDeleteUser(user)}
                      >
                        Delete
                      </Button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </Table>
        )}

        {/* Create User Modal */}
        <Modal show={showCreate()} onhide={() => setShowCreate(false)}>
          <Modal.Header closeButton>
            <Modal.Title>Create User</Modal.Title>
          </Modal.Header>
          <Modal.Body>
            {error() && (
              <Alert variant="danger" dismissible onclose={() => setError("")}>
                {error()}
              </Alert>
            )}
            <Form.Group class="mb-3">
              <Form.Label>Username</Form.Label>
              <Form.Control
                type="text"
                value={newUsername()}
                onInput={(e: any) => setNewUsername(e.target.value)}
                placeholder="Enter username"
              />
            </Form.Group>
            <Form.Group class="mb-3">
              <Form.Label>Password</Form.Label>
              <Form.Control
                type="password"
                value={newPassword()}
                onInput={(e: any) => setNewPassword(e.target.value)}
                placeholder="Enter password (min 4 chars)"
              />
            </Form.Group>
            <Form.Group class="mb-3">
              <Form.Label>Role</Form.Label>
              <Form.Select
                value={newRole()}
                onChange={(e: any) => setNewRole(e.target.value)}
              >
                <option value="user">User</option>
                <option value="admin">Admin</option>
              </Form.Select>
            </Form.Group>
          </Modal.Body>
          <Modal.Footer>
            <Button variant="secondary" onclick={() => setShowCreate(false)}>
              Cancel
            </Button>
            <Button variant="primary" onclick={() => handleCreateUser()} disabled={submitting()}>
              {submitting() ? "Creating..." : "Create"}
            </Button>
          </Modal.Footer>
        </Modal>

        {/* Reset Password Modal */}
        <Modal show={showResetPwd()} onhide={() => setShowResetPwd(false)}>
          <Modal.Header closeButton>
            <Modal.Title>Reset Password - {resetUsername()}</Modal.Title>
          </Modal.Header>
          <Modal.Body>
            {error() && (
              <Alert variant="danger" dismissible onclose={() => setError("")}>
                {error()}
              </Alert>
            )}
            <Form.Group class="mb-3">
              <Form.Label>New Password</Form.Label>
              <Form.Control
                type="password"
                value={resetPassword()}
                onInput={(e: any) => setResetPassword(e.target.value)}
                placeholder="Enter new password (min 4 chars)"
              />
            </Form.Group>
          </Modal.Body>
          <Modal.Footer>
            <Button variant="secondary" onclick={() => setShowResetPwd(false)}>
              Cancel
            </Button>
            <Button variant="primary" onclick={() => handleResetPassword()} disabled={resettingPwd()}>
              {resettingPwd() ? "Resetting..." : "Reset Password"}
            </Button>
          </Modal.Footer>
        </Modal>
      </Container>
    </>
  );
}
