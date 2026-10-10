from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class LoginRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    username: str = Field(min_length=1, max_length=64)
    pin: str | None = Field(default=None, min_length=4, max_length=12)
    phone_number: str | None = Field(default=None, max_length=20)
    device_id: str | None = Field(default=None, max_length=128)
    device_name: str | None = Field(default=None, max_length=128)

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value: str) -> str:
        return value.lower()


class UserResponse(BaseModel):
    user_id: str
    username: str
    name: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_at: datetime
    user: UserResponse
    server_time: str | None = None
    server_today: str | None = None
    day_cutoff_hours: int = 4


class LogoutResponse(BaseModel):
    detail: str