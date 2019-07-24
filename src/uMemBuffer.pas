unit uMemBuffer;

interface

uses
  Classes, SysUtils, Windows,uSyncObj;

type
  TuMemBuffer = class
  protected
    FSize, FCapacity, FIncrement: Integer;
    FMemory: PByte;
    FForwardOffsetSize : Integer;
    FLock: TFixedCriticalSection;
    procedure EnsureCapacity(NewSize: Integer);
    function GetLeftSize:Integer;
    function GetOffSetPointer : PByte;
    function GetMemory():PByte;
  public
    constructor Create(InitialCapacity: Integer = 8192; Increment: Integer = 8192);
    destructor Destroy; override;

    procedure Lock; inline;
    procedure Unlock; inline;
    function TryLock():Boolean;
    procedure Append(Buf: PByte; Size: Integer); inline;
    procedure AppendString(const S: AnsiString); inline;
    procedure AppendStream(Stream: TStream; Size: Integer); inline;
    procedure AppendBuffer(ASource: TuMemBuffer); inline;
    function Extract(Buf: PByte; Size: Integer): Integer;
    procedure Clear; inline;  //清空所有内存
    procedure ForwardOffset(Size:Integer); //把当前的数据指针往前移动 并不清理掉任何内存
    procedure CompactionMemory(); //紧缩内存把 头部空余的内存清理掉。
    procedure CheckCompactionMemory();
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
    procedure SaveToFile(const FileName:String);
    procedure Trunc(); //截断数据长度为0
    procedure GrowUp();//扩容数据
    procedure SizeAdd(Value:Integer); //外部手动调用增加size 通常是在使用OffsetMemory 获取原始地址后 move了内存而进行增加的
    property Size: Integer read FSize;
    property Memory: PByte read GetMemory ;
    property LeftSize:Integer read GetLeftSize; //在不进行扩容的当前还剩余多少大小
    property OffsetMemory:PByte read GetOffSetPointer;
    property Capacity : Integer read FCapacity;
    property ForwardOffsetSize :Integer read FForwardOffsetSize;
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
  FLock := TFixedCriticalSection.Create;
  GetMem(FMemory, InitialCapacity);
  if FMemory = Nil then
    raise EOutOfMemory.Create('TuMemBuffer.Create');
  FCapacity := InitialCapacity;
  FIncrement := Increment;
  FForwardOffsetSize := 0;
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

procedure TuMemBuffer.Append(Buf: PByte; Size: Integer);
begin
  EnsureCapacity(FSize + Size + FForwardOffsetSize);
  Move(Buf^, PByte(Cardinal(GetMemory()) + FSize)^, Size);
  Inc(FSize, Size);
end;

procedure TuMemBuffer.AppendString(const S: AnsiString);
begin
  Self.Append(@S[1], Length(S));
end;

procedure TuMemBuffer.AppendStream(Stream: TStream; Size: Integer);
begin
  EnsureCapacity(FSize + Size + FForwardOffsetSize);
  Stream.Read(PByte(Cardinal(GetMemory()) + FSize)^, Size);
  Inc(FSize, Size);
end;

procedure TuMemBuffer.AppendBuffer(ASource: TuMemBuffer);
begin
  if ASource.FSize > 0 then
    Append(ASource.GetMemory(), ASource.FSize);
end;

procedure TuMemBuffer.Lock;
begin
  FLock.Enter;
end;

procedure TuMemBuffer.Unlock;
begin
  FLock.Leave;
end;

function TuMemBuffer.Extract(Buf: PByte; Size: Integer): Integer;
var
  ToCopy: Integer;
  M:PByte;
begin
  Result := 0;
  if Size > 0 then
  begin
    M := GetMemory();
    ToCopy := Min(Size, FSize);
    if Buf <> Nil then
      Move(M, Buf^, ToCopy);

    Inc(FForwardOffsetSize,ToCopy);
    Dec(FSize, ToCopy);
    Result := ToCopy;
  end;
end;

procedure TuMemBuffer.ForwardOffset(Size: Integer);
begin
  Size := Min(Size, FSize);
  Inc(FForwardOffsetSize,Size);
  Dec(FSize, Size);
end;

function TuMemBuffer.GetLeftSize: Integer;
begin
  Result := FCapacity - FSize - FForwardOffsetSize  ;
end;

function TuMemBuffer.GetMemory: PByte;
begin
  Result := PByte(Cardinal(FMemory) + FForwardOffsetSize);
end;

function TuMemBuffer.GetOffSetPointer: PByte;
begin
 Result := PByte(Cardinal(GetMemory()) + FSize);
end;

procedure TuMemBuffer.GrowUp;
begin
  EnsureCapacity(FCapacity + FIncrement);
end;

procedure TuMemBuffer.CheckCompactionMemory;
begin
  if FForwardOffsetSize > (FCapacity shr 1) then
  begin
    CompactionMemory();
  end;
end;

procedure TuMemBuffer.Clear;
begin
  Extract(nil, Size);
  FForwardOffsetSize := 0;
end;

procedure TuMemBuffer.CompactionMemory;
var
  M : PByte;
begin
  M := GetMemory();
  if FForwardOffsetSize <= 0 then
    Exit;

  if FSize > 0 then
  begin
    Move(M^,FMemory^,FSize);
  end;

  FForwardOffsetSize := 0;
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

procedure TuMemBuffer.SaveToFile(const FileName: String);
var
  FileStream :TFileStream;
begin
  FileStream := TFileStream.Create(FileName,fmCreate);
  Try
    FileStream.Write(Self.Memory^,Self.Size);
  Finally
    FileStream.Free;
  End;
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

function TuMemBuffer.TryLock: Boolean;
begin
  Result := FLock.TryEnter();
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
  SetString(Result, PAnsiChar(FMemory), Avail);
  ForwardOffset(Avail);
end;

end.
