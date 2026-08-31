# API (.NET Framework 4.7.2)

POST /api/register
{
    "username": "john",
    "email": "john@example.com",
    "password": "MyPassword123!"
}

POST /api/auth/login
{
    "username": "john",
    "password": "MyPassword123!"
}

GET /api/user/me
Authorization: Bearer TOKEN_GOES_HERE
{
    "success": true,
    "user": {
        "id": 1,
        "username": "john",
        "email": "john@example.com"
    }
}

POST /api/auth/logout
Authorization: Bearer TOKEN_GOES_HERE

POST /api/state/check
Authorization: Bearer TOKEN_GOES_HERE
