# API (.NET Framework 4.7.2)

# API Endpoints

All requests and responses use `application/json`.

---

## Register

**POST** `/api/register`

### Request

```json
{
  "username": "john",
  "email": "john@example.com",
  "password": "MyPassword123!"
}
```

### Response

```json
{
  "success": true,
  "message": "Registration successful."
}
```

---

## Login

**POST** `/api/auth/login`

### Request

```json
{
  "username": "john",
  "password": "MyPassword123!"
}
```

### Response

```json
{
  "success": true,
  "message": "Login successful.",
  "token": "TOKEN_GOES_HERE",
  "expiresAt": "2026-09-01T01:30:00Z",
  "user": {
    "id": 1,
    "username": "john",
    "email": "john@example.com"
  }
}
```

Use the returned `token` for authenticated endpoints.

---

## Get Current User

**GET** `/api/user/me`

### Headers

```http
Authorization: Bearer TOKEN_GOES_HERE
```

### Response

```json
{
  "success": true,
  "user": {
    "id": 1,
    "username": "john",
    "email": "john@example.com"
  }
}
```

---

## Logout

**POST** `/api/auth/logout`

### Headers

```http
Authorization: Bearer TOKEN_GOES_HERE
```

### Response

```json
{
  "success": true,
  "message": "Logout successful."
}
```

The token is revoked and can no longer be used for authenticated requests.

---

## Check Content State

**POST** `/api/state/check`

### Headers

```http
Authorization: Bearer TOKEN_GOES_HERE
Content-Type: application/json
```

### Request

```json
{
  "contentObjectId": 1001,
  "state": {
    "hasCompletedIntro": true,
    "level": 7,
    "hasSubscription": true
  }
}
```

The API retrieves the requirements for the specified `contentObjectId` from SQL Server, deserializes the stored JSON into the `Requirements` object, and compares it against the supplied state.

### Access Granted

```json
{
  "success": true,
  "accessGranted": true,
  "contentObjectId": 1001,
  "message": "All required conditions have been fulfilled."
}
```

### Access Denied

```json
{
  "success": true,
  "accessGranted": false,
  "contentObjectId": 1001,
  "message": "Required conditions have not been fulfilled."
}
```

---

## Authentication

Authenticated endpoints require a bearer token:

```http
Authorization: Bearer TOKEN_GOES_HERE
```

The token is returned by `/api/auth/login` and remains valid until it expires or is revoked by `/api/auth/logout`.
