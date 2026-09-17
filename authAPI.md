# Auth API Documentation

This document outlines the available authentication (`auth`) commands for the API.

## Table of Contents

- [`auth/authorization_url`](#authauthorization_url)
- [`auth/login`](#authlogin)
- [`auth/logout`](#authlogout)
- [`auth/me`](#authme)
- [`auth/providers`](#authproviders)
- [`auth/token/create`](#authtokencreate)
- [`auth/token/revoke`](#authtokenrevoke)
- [`auth/tokens`](#authtokens)
- [`auth/user`](#authuser) 🔒 *Admin*
- [`auth/user/create`](#authusercreate) 🔒 *Admin*
- [`auth/user/delete`](#authuserdelete) 🔒 *Admin*
- [`auth/user/disable`](#authuserdisable) 🔒 *Admin*
- [`auth/user/enable`](#authuserenable) 🔒 *Admin*
- [`auth/user/providers`](#authuserproviders)
- [`auth/user/unlink_provider`](#authuserunlink_provider) 🔒 *Admin*
- [`auth/user/update`](#authuserupdate)
- [`auth/users`](#authusers) 🔒 *Admin*

---

## `auth/authorization_url`

**Summary:** Get OAuth authorization URL for authentication.

**Description:** Get OAuth authorization URL for authentication. For OAuth providers (like Home Assistant), this returns the URL that the user should visit in their browser to authorize the application.

**Returns:** `object with string keys and string values`

### Parameters

- `provider_id` <kbd>REQUIRED</kbd> (`string`): The provider ID (e.g., "hass").
- `return_url` (`string`): URL to redirect to after OAuth completes.

---

## `auth/login`

**Summary:** Authenticate user with credentials via WebSocket.

**Description:** Authenticate user with credentials via WebSocket. This command allows clients to authenticate over the WebSocket connection using username/password or other provider-specific credentials.

**Returns:** `object with string keys and Any values`

### Parameters

- `username` (`string`): Username for authentication (for builtin provider).
- `password` (`string`): Password for authentication (for builtin provider).
- `provider_id` (`string`): The login provider ID (defaults to "builtin").
- `device_name` (`string`): Optional device name for the token (e.g., "iPhone 15", "Desktop PC").
- `extra_credentials` <kbd>REQUIRED</kbd> (`Any`): Additional provider-specific credentials.

---

## `auth/logout`

**Summary:** Logout current user by revoking the current token.

**Returns:** `null`

*(No parameters)*

---

## `auth/me`

**Summary:** Get current authenticated user information.

**Returns:** `User`

*(No parameters)*

---

## `auth/providers`

**Summary:** Get list of available authentication providers.

**Description:** Get list of available authentication providers. Returns information about all available login providers including whether they require OAuth redirect flow.

**Returns:** `Array of object with string keys and Any values`

*(No parameters)*

---

## `auth/token/create`

**Summary:** Create a new long-lived access token for current user or another user (admin only).

**Description:** Create a new long-lived access token for current user or another user (admin only). Long-lived tokens are intended for external integrations and API access. They expire after 10 years and do NOT auto-renew on use. Short-lived tokens (for regular user sessions) are only created during login and auto-renew on each use (sliding 30-day expiration window).

**Returns:** `string`

### Parameters

- `name` <kbd>REQUIRED</kbd> (`string`): The name/description for the token (e.g., "Home Assistant", "Mobile App").
- `user_id` (`string`): Optional user ID to create token for (admin only).

---

## `auth/token/revoke`

**Summary:** Revoke an auth token.

**Returns:** `null`

### Parameters

- `token_id` <kbd>REQUIRED</kbd> (`string`): The token ID to revoke.

---

## `auth/tokens`

**Summary:** Get current user's auth tokens or another user's tokens (admin only).

**Returns:** `Array of AuthToken`

### Parameters

- `user_id` (`string`): Optional user ID to get tokens for (admin only).

---

## `auth/user` 🔒 *Admin*

**Summary:** Get user by ID (admin only).

**Returns:** `User`

### Parameters

- `user_id` <kbd>REQUIRED</kbd> (`string`): The user ID.

---

## `auth/user/create` 🔒 *Admin*

**Summary:** Create a new user with built-in authentication (admin only).

**Returns:** `User`

### Parameters

- `username` <kbd>REQUIRED</kbd> (`string`): The username (minimum 2 characters).
- `password` <kbd>REQUIRED</kbd> (`string`): The password (minimum 8 characters).
- `role` (`string`): User role - "admin" or "user" (default: "user").
- `display_name` (`string`): Optional display name.
- `avatar_url` (`string`): Optional avatar URL.
- `player_filter` (`Array of string`): Optional list of player IDs user has access to.
- `provider_filter` (`Array of string`): Optional list of provider instance IDs user has access to.

---

## `auth/user/delete` 🔒 *Admin*

**Summary:** Delete user account (admin only).

**Returns:** `null`

### Parameters

- `user_id` <kbd>REQUIRED</kbd> (`string`): The user ID.

---

## `auth/user/disable` 🔒 *Admin*

**Summary:** Disable user account (admin only).

**Returns:** `null`

### Parameters

- `user_id` <kbd>REQUIRED</kbd> (`string`): The user ID.

---

## `auth/user/enable` 🔒 *Admin*

**Summary:** Enable user account (admin only).

**Returns:** `null`

### Parameters

- `user_id` <kbd>REQUIRED</kbd> (`string`): The user ID.

---

## `auth/user/providers`

**Summary:** Get current user's linked authentication providers.

**Returns:** `Array of object with string keys and Any values`

*(No parameters)*

---

## `auth/user/unlink_provider` 🔒 *Admin*

**Summary:** Unlink authentication provider from user (admin only).

**Returns:** `boolean`

### Parameters

- `user_id` <kbd>REQUIRED</kbd> (`string`): The user ID.
- `provider_type` <kbd>REQUIRED</kbd> (`string`): Provider type to unlink.

---

## `auth/user/update`

**Summary:** Update user profile information.

**Description:** Update user profile information. Users can update their own profile. Admins can update any user including role and password.

**Returns:** `User`

### Parameters

- `user_id` (`string`): User ID to update (optional, defaults to current user).
- `username` (`string`): New username (optional).
- `display_name` (`string`): New display name (optional).
- `avatar_url` (`string`): New avatar URL (optional).
- `password` (`string`): New password (optional, minimum 8 characters).
- `role` (`string`): New role - "admin" or "user" (optional, set by admin only).
- `preferences` (`object with string keys and Any values`): User preferences dict (completely replaces existing, optional).
- `player_filter` (`Array of string`): List of player IDs user has access to (set by admin only, optional).
- `provider_filter` (`Array of string`): List of provider instance IDs user has access to (set by admin only, optional).

---

## `auth/users` 🔒 *Admin*

**Summary:** Get all users (admin only).

**Description:** Get all users (admin only). System users are excluded from the list.

**Returns:** `Array of User`

*(No parameters)*
