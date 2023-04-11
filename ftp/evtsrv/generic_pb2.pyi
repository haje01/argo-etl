from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class Event(_message.Message):
    __slots__ = ["name", "payload"]
    NAME_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_FIELD_NUMBER: _ClassVar[int]
    name: str
    payload: bytes
    def __init__(self, name: _Optional[str] = ..., payload: _Optional[bytes] = ...) -> None: ...

class EventSource(_message.Message):
    __slots__ = ["config", "name"]
    CONFIG_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    config: bytes
    name: str
    def __init__(self, name: _Optional[str] = ..., config: _Optional[bytes] = ...) -> None: ...
