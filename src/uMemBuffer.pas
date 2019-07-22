unit uMemBuffer;

interface

uses
  Classes, SysUtils, Windows,SyncObjs;

type
  TuMemBuffer = class
  protected
    FSize, FCapacity, FIncrement: Integer;
    FMemory: PAnsiChar;
    FLock: TCriticalSection;
    procedure EnsureCapacity(NewSize: Integer);
    function GetLeftSize:Integer;
    function GetOffSetPointer : PAnsiChar;
  public
    constructor Create(InitialCapacity: Integer = 8192; Increment: Integer = 8192);
    destructor Destroy; override;

    procedure Lock; inline;
    procedure Unlock; inline;
    procedure Append(Buf: PAnsiChar; Size: Integer); inline;
    procedure AppendString(const S: AnsiString); inline;
    procedure AppendStream(Stream: TStream; Size: Integer); inline;
    procedure AppendBuffer(ASource: TuMemBuffer); inline;
    function Extract(Buf: PAnsiChar; Size: Integer): Integer;
    function Delete(Size: Integer): Integer; inline;
    procedure Clear; inline;

    function IsInteger: Boolean;
    function IsInt64: Boolean;
    function IsByte: Boolean;
    function IsAnsiChar: Boolean;

    function ReadInteger: Integer;
    function ReadCardinal: Cardinal;
    function ReadInt64: Int64;
    function ReadByte: Byte;
    function ReadWord: Word;
    function ReadAnsiChar: AnsiChar;
    function ReadBlock(BlockSize: Integer): AnsiString;
    procedure Trunc(); //截断数据长度为0
    procedure SizeAdd(Value:Integer); //外部手动调用增加size 通常是在使用OffsetMemory 获取原始地址后 move了内存而进行增加的
    property Size: Integer read FSize;
    property Memory: PAnsiChar read FMemory;
    property LeftSize:Integer read GetLeftSize; //在不进行扩容的当前还剩余多少大小
    property OffsetMemory:PAnsiChar read GetOffSetPointer;
  end;

implementation

function Min(const A, B: Integer): Integer; inline;
begin
  if A < B then
    Result := A
  else
    Result := B;
end;

constructor TuMemBuffer.Create(InitialCapacity, Increment: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  GetMem(FMemory, InitialCapacity);
  if FMemory = Nil then
    raise EOutOfMemory.Create('TuMemBuffer.Create');
  FCapacity := InitialCapacity;
  FIncrement := Increment;
  FSize := 0;
end;

destructor TuMemBuffer.Destroy;
begin
  FreeMem(FMemory);
  FLock.Free;
  inherited Destroy;
end;

procedure TuMemBuffer.EnsureCapacity(NewSize: Integer);
var
  NewCapacity: Integer;
begin
  if NewSize > FCapacity then
  begin
    if NewSize mod FIncrement = 0 then
      NewCapacity := NewSize
    else
      NewCapacity := FIncrement * ((NewSize div FIncrement) + 1);

    Assert(NewCapacity >= NewSize);
    ReallocMem(FMemory, NewCapacity);
    FCapacity := NewCapacity;
  end;
end;

procedure TuMemBuffer.Append(Buf: PAnsiChar; Size: Integer);
begin
  EnsureCapacity(FSize + Size);
  Move(Buf^, PAnsiChar(Cardinal(FMemory) + FSize)^, Size);
  Inc(FSize, Size);
end;

procedure TuMemBuffer.AppendString(const S: AnsiString);
begin
  Self.Append(@S[1], Length(S));
end;

procedure TuMemBuffer.AppendStream(Stream: TStream; Size: Integer);
begin
  EnsureCapacity(FSize + Size);
  Stream.Read(PAnsiChar(Cardinal(FMemory) + FSize)^, Size);
  Inc(FSize, Size);
end;

procedure TuMemBuffer.AppendBuffer(ASource: TuMemBuffer);
begin
  if ASource.FSize > 0 then
    Append(ASource.FMemory, ASource.FSize);
end;

procedure TuMemBuffer.Lock;
begin
  FLock.Enter;
end;

procedure TuMemBuffer.Unlock;
begin
  FLock.Leave;
end;

function TuMemBuffer.Extract(Buf: PAnsiChar; Size: Integer): Integer;
var
  ToCopy: Integer;
begin
  Result := 0;
  if Size > 0 then
  begin
    ToCopy := Min(Size, FSize);
    if Buf <> Nil then
      Move(FMemory^, Buf^, ToCopy);
    if FSize <> ToCopy then
      Move(PAnsiChar(Cardinal(FMemory) + Size)^, FMemory^, FSize - Size);

    Dec(FSize, ToCopy);
    Result := ToCopy;
  end;
end;

function TuMemBuffer.GetLeftSize: Integer;
begin
  Result := FCapacity - FSize ;
end;

function TuMemBuffer.GetOffSetPointer: PAnsiChar;
begin
 Result := PAnsiChar(Cardinal(FMemory) + FSize);
end;

function TuMemBuffer.Delete(Size: Integer): Integer;
begin
  Result := Extract(nil, Size);
end;

procedure TuMemBuffer.Clear;
begin
  Extract(nil, Size);
end;

function TuMemBuffer.IsInteger: Boolean;
begin
  Result := Size >= Sizeof(Integer);
end;

function TuMemBuffer.IsInt64: Boolean;
begin
  Result := Size >= Sizeof(Int64);
end;

function TuMemBuffer.IsByte: Boolean;
begin
  Result := Size >= Sizeof(Byte);
end;

function TuMemBuffer.IsAnsiChar: Boolean;
begin
  Result := Size >= Sizeof(AnsiChar);
end;

function TuMemBuffer.ReadInteger: Integer;
begin
  Extract(@Result, Sizeof(Integer));
end;

function TuMemBuffer.ReadInt64: Int64;
begin
  Extract(@Result, Sizeof(Int64));
end;

function TuMemBuffer.ReadByte: Byte;
begin
  Extract(@Result, Sizeof(Result));
end;

function TuMemBuffer.ReadCardinal: Cardinal;
begin
  Extract(@Result, Sizeof(Result));
end;

function TuMemBuffer.ReadWord: Word;
begin
  Extract(@Result, Sizeof(Result));
end;

procedure TuMemBuffer.SizeAdd(Value: Integer);
begin
  if FSize + Value > FCapacity then
  begin
    raise Exception.Create('TuMemBuffer.SizeAdd 预计增加的大小超出了缓冲区总大小');
  end else
  begin
    FSize := FSize + Value;
  end;
end;

procedure TuMemBuffer.Trunc;
begin
  FSize := 0;
end;

function TuMemBuffer.ReadAnsiChar: AnsiChar;
begin
  Extract(@Result, Sizeof(@Result));
end;

function TuMemBuffer.ReadBlock(BlockSize: Integer): AnsiString;
var
  Avail: Integer;
begin
  if BlockSize > Size then
    raise Exception.Create('!!!');

  Avail := Min(Size, BlockSize);
  SetString(Result, FMemory, Avail);
  Delete(Avail);
end;

end.
