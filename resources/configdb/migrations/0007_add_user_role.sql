-- Add role column to users table for admin/user distinction
ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user';

-- Existing admin user (if any) should get admin role
UPDATE users SET role = 'admin' WHERE username = 'admin';
