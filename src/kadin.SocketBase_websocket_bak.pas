unit kadin.SocketBase;

interface
uses
  WinSock2,SysUtils,uMemBuffer,Winapi.Windows,kadin.WebSocket,Math,System.Classes,System.Hash,System.NetEncoding;
Type
  ESelectSocketError = class(Exception)
    ErrorCode : Integer;
  end;

  TKDRecvAbleSocket = class;

  TKDSocketCloseEventType = (sceRead,sceWrite,sceSelfClose,sceError,sceRemoteClose,sceHandShark,sceHandShareAttack);

  TKDSocketCloseEvent = procedure (Sender:TKDRecvAbleSocket ; CloseEventType : TKDSocketCloseEventType ; ErrorCode:Integer) of Object;

  TKDSocketRecvTextEvent = procedure (Sender:TKDRecvAbleSocket ; const Text:String);
  TKDSocketBinaryFrameEvent = procedure (Sender:TKDRecvAbleSocket ; const pBuffer:Pointer ; Size : Cardinal);

  //注意 Property 可能会抛异常 函数类的不会抛异常
  TKDSocket = class
  protected
     _fd : TSocket;
     _addr_in : TSockAddrIn;
     _isBlockMode: Boolean;
     procedure OnSocketConnected();virtual;
     procedure OnSocketError(ErrorCode:Integer);virtual;
     procedure OnSocketClose(Event:TKDSocketCloseEventType ; ErrorCode:Integer);virtual;
     function GetRecvbBufferSize():Integer;virtual;
     function GetSendBufferSize():Integer;virtual;
     procedure SetRecvBufferSize(Size:Integer);virtual;
     procedure SetSendBufferSize(Size:Integer);virtual;
     procedure SetBlockMode(isBlock:Boolean);
  public
    constructor Create();
    constructor CreateBySocket(Socket:TSocket);

    function Close(Event:TKDSocketCloseEventType ; ErrorCode:Integer):Boolean;
    function Send(pData:PByte;Size:Integer):Integer;
    function Recv(pData:PByte;Size:Integer):Integer;
    function Connect(const IP:String;Port:Integer):Integer;
    function Bind(const IP:string;Port:Integer):Integer;
    function Accept(var fd:TSocket ; var addr_in:TSockAddrIn ):Integer;

    property SendBufferSize : Integer Read GetSendBufferSize write SetSendBufferSize;
    property RecvBufferSize : Integer read GetRecvbBufferSize write SetRecvBufferSize;
    property BlockMode : Boolean read _isBlockMode write SetBlockMode;
  end;

  //具有接受数据能力的Socket
  TKDRecvAbleSocket = class(TKDSocket)
  private
    FRecivedBuffer : TuMemBuffer;  //待处理的内容
    FSendBuffer : TuMemBuffer;
    FOnText: TKDSocketRecvTextEvent;
    FOnBinary: TKDSocketBinaryFrameEvent;
    FOnClose: TKDSocketCloseEvent;
    FIsHandSharked:Boolean;
    procedure SetOnBinary(const Value: TKDSocketBinaryFrameEvent);
    procedure SetOnClose(const Value: TKDSocketCloseEvent);
    procedure SetOnText(const Value: TKDSocketRecvTextEvent);     //待发送的内容
    procedure SetSendBufferSize(Size:Integer);virtual;
  protected
     FSocketSendBufferSize : Integer;
    function TryRecv():Boolean;
    procedure TrySend();virtual;
    procedure TryParserWebSocketHandShark();
    procedure RecvWebSocketFrame(var Frame:TWebSocketFrame);
    procedure OnSocketConnected();virtual;
    procedure OnSocketError(ErrorCode:Integer);virtual;
    procedure OnSocketClose(Event:TKDSocketCloseEventType ; ErrorCode:Integer);virtual;
  public
    procedure Run();
    constructor Create(RecvBufferSize : Integer = 8192 ;SendBufferSize:Integer = 8192);
    Property OnText : TKDSocketRecvTextEvent read FOnText write SetOnText;
    property OnBinary : TKDSocketBinaryFrameEvent read FOnBinary write SetOnBinary;
    property OnClose : TKDSocketCloseEvent read FOnClose write SetOnClose;
  end;

implementation
var
   wsaData : TWSADATA;
procedure RaiseSocketException(ErrorCode:Integer);
begin
  raise ESelectSocketError.CreateFmt('Socket Error : %s WSAGetLastError:%d',[SysErrorMessage(ErrorCode),ErrorCode]);
end;

{ TSockeBase }

function TKDSocket.Accept(var fd: TSocket; var addr_in: TSockAddrIn): Integer;
var
  fdset : TFdSet;
  tv : TTimeVal;
  addr_in_size : Integer;
  nErr : Integer;
begin

  Result := SOCKET_ERROR - 1;
	 FD_ZERO( fdset );
	_FD_SET( _fd, &fdset );

	tv.tv_sec := 0;
	tv.tv_usec := 1;

	nErr := select( integer(_fd + 1), @fdset, nil, nil, @tv );
	if ( nErr < 0 ) then
  begin
		Result := WSAGetLastError();
  end else if ( nErr > 0 ) then
  begin
		addr_in_size := sizeof(addr_in);
		fd := WinSock2.accept( _fd, PSockAddr(@addr_in), @addr_in_size );
		if ( fd = INVALID_SOCKET ) then
    begin
      Result := WSAGetLastError();
    end else
    begin
      Result := 0;   
    end;
	end
end;

function TKDSocket.Bind(const IP: string; Port: Integer): Integer;
var
  pHost : PHostEnt;
  IPAnsi:AnsiString;
  SocktAddr: TSockAddr;
begin
  IPAnsi := AnsiString(IP);
  pHost := gethostbyname(PAnsiChar(IPAnsi));
  if pHost <> nil then
  begin
    _addr_in.sin_port := htons(Word(Port));
    //_addr_in.sin_addr.S_addr := PCardinal(pHost.h_addr_list)^;
    _addr_in.sin_addr.S_addr := INADDR_ANY;
    _addr_in.sin_family := PF_INET;
    Move(_addr_in, SocktAddr, SizeOf(SocktAddr));
    Result := WinSock2.bind(_fd,SocktAddr,SizeOf(SocktAddr));
    if Result = 0 then
    begin
      Result := WinSock2.listen(_fd,8);
      if Result <> 0  then
        Result := WSAGetLastError();
    end else
    begin
      Result := WSAGetLastError();
    end;
  end else
  begin
    Result := WSAGetLastError();
  end;
end;

function TKDSocket.Close(Event:TKDSocketCloseEventType ; ErrorCode:Integer):Boolean;
begin
	if ( _fd <> INVALID_SOCKET ) then
  begin
    closesocket( _fd );
		_fd := INVALID_SOCKET;
    Result := True;
    OnSocketClose(Event,ErrorCode);
  end else
  begin
    Result := False;
  end;
end;

function TKDSocket.Connect(const IP: String; Port: Integer): Integer;
var
  IPAddr: AnsiString;
  SocktAddr: TSockAddr;
begin
  // 初始化socket
  Close(sceSelfClose,0);
  FillChar(_addr_in,0,SizeOf(_addr_in));
  _addr_in.sin_family := PF_INET;
  IPAddr := AnsiString(IP);
  _addr_in.sin_addr.S_addr := inet_addr(PAnsiChar(IPAddr));
  _addr_in.sin_port := htons(Port);

  Move(_addr_in, SocktAddr, SizeOf(SocktAddr));
  // 连接
  Result := WinSock2.connect(_fd, SocktAddr, SizeOf(SocktAddr));
  if Result <> 0 then // 连接失败
  begin
    Result := WSAGetLastError();
    Close(sceError,Result);
  end;
end;

constructor TKDSocket.Create;
begin
  _fd := WinSock2.socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
end;

constructor TKDSocket.CreateBySocket(Socket: TSocket);
begin
   _fd := Socket;
end;

function TKDSocket.GetRecvbBufferSize: Integer;
var
 ResultLen : Integer;
 Ret : Integer;
begin
  ResultLen := 4;
  Ret := getsockopt(_fd,SOL_SOCKET,SO_RCVBUF,@Result,ResultLen);
  if Ret <>  0 then
  begin
    Result := Ret;
  end;
end;

function TKDSocket.GetSendBufferSize: Integer;
var
 ResultLen : Integer;
 Ret : Integer;
begin
  ResultLen := 4;
  Ret := getsockopt(_fd,SOL_SOCKET,SO_SNDBUF,@Result,ResultLen);
  if Ret <>  0 then
  begin
    Result := Ret;
  end;
end;

procedure TKDSocket.OnSocketClose(Event:TKDSocketCloseEventType ; ErrorCode:Integer);
begin

end;

procedure TKDSocket.OnSocketConnected;
begin

end;

procedure TKDSocket.OnSocketError(ErrorCode: Integer);
begin

end;

function TKDSocket.Recv(pData: PByte; Size: Integer): Integer;
begin
  Result := WinSock2.recv(_fd,pData^,Size,0);

  if Result = 0 then
  begin
    Close(sceRead,0);
    Result := 0;
    Exit;
  end;

  if Result = SOCKET_ERROR then
  begin
    Result := WSAGetLastError();
    if Result <> WSAEWOULDBLOCK then
    begin
      OnSocketError(Result);
      Close(sceRead,Result);
    end else
    begin
      Result := 0; //接收缓冲区不足
    end;
  end;
end;

function TKDSocket.Send(pData: PByte; Size: Integer): Integer;
begin
  Result := WinSock2.send(_fd, pData^, Size, 0);
  if Result = SOCKET_ERROR then
  begin
    Result := WSAGetLastError;
    if (Result <> WSAEWOULDBLOCK) then
    begin
      OnSocketError(Result);
      Close(sceWrite,Result);
    end;
  end;
end;

procedure TKDSocket.SetBlockMode(isBlock: Boolean);
var
  block : Cardinal;
  ret : Integer;
begin
  if isBlock then
    block := 0
  else
    block := 1;

  ret := ioctlsocket( _fd, Integer(FIONBIO), block );

  if ret <> 0 then
    RaiseSocketException(ret);
end;

procedure TKDSocket.SetRecvBufferSize(Size: Integer);
var
  ResultLen , Ret :Integer;
begin
  ResultLen := 4;
  Ret := setsockopt( _fd, SOL_SOCKET, SO_RCVBUF, @Size, ResultLen );
  if Ret <> 0 then
    RaiseSocketException(Ret);
end;

procedure TKDSocket.SetSendBufferSize(Size: Integer);
var
  ResultLen , Ret :Integer;
begin
  ResultLen := 4;
  Ret := setsockopt( _fd, SOL_SOCKET, SO_SNDBUF, @Size, ResultLen );
  if Ret <> 0 then
    RaiseSocketException(Ret);
end;

{ TKDRecvAbleSocket }

constructor TKDRecvAbleSocket.Create(RecvBufferSize, SendBufferSize: Integer);
begin
  inherited Create();
  FRecivedBuffer := TuMemBuffer.Create(RecvBufferSize);
  FSendBuffer := TuMemBuffer.Create(SendBufferSize);
  FIsHandSharked := False;
  FSocketSendBufferSize := 1024;
end;

procedure TKDRecvAbleSocket.OnSocketClose(Event:TKDSocketCloseEventType ; ErrorCode:Integer);
begin
  if Assigned(FOnClose) then
  begin
    FOnClose(Self,Event,ErrorCode);
  end;
end;

procedure TKDRecvAbleSocket.OnSocketConnected;
begin

end;

procedure TKDRecvAbleSocket.OnSocketError(ErrorCode: Integer);
begin

end;

procedure TKDRecvAbleSocket.RecvWebSocketFrame(var Frame: TWebSocketFrame);
var
  StrBytes:TBytes;
  Text :String;
  StrLen:Integer;
  Header : array [0..13] of Byte;
  HeadSize : Integer;
  State : Integer;
  AnsiText :String;
begin
  case Frame.Opcode of
    OPCODE_TEXT_FRAME :
    begin
      if Assigned(FOnText) then
      begin
        SetLength(Text,Frame.Len);
        StrLen := Utf8ToUnicode(@Text[1],Frame.Len + 1,PAnsiChar(Frame.PData),Frame.Len);
        if StrLen > 0 then
        begin
          SetLength(Text,StrLen - 1);
        end;
        FOnText(Self,Text);
      end;
    end;
    OPCODE_BINARY_FRAME:
    begin
      if Assigned(FOnBinary) then
      begin
        FOnBinary(Self,Frame.PData,Frame.Len);
      end;
    end;
    OPCODE_CLOSE_FRAME:
    Begin
      Self.Close(sceRemoteClose,0);
    End;
    OPCODE_PING_FRAME:
    Begin
       State := PacketWebSocketFrame(OPCODE_PONG_FRAME,nil,0,0,@Header[0],HeadSize);
       if State = 0 then
       begin
         FSendBuffer.Append(@Header[0],HeadSize);
       end;
    End;
    OPCODE_PONG_FRAME:
    Begin
      //不应该收到Pong 才对
    End;
  end;
end;

procedure TKDRecvAbleSocket.Run;
var
  PBuffer:Pointer;
  Frame:TWebSocketFrame;
  ProcessBytes:Integer;
begin
  if TryRecv() then
  begin
    if not FIsHandSharked then
    begin
      TryParserWebSocketHandShark();
    end else
    begin
      PBuffer := FRecivedBuffer.Memory;
      ProcessBytes := UnPackWebSocketFrame(PBuffer,FRecivedBuffer.Size,Frame);
      if ProcessBytes > 0 then
      begin
        RecvWebSocketFrame(Frame);
        FRecivedBuffer.ForwardOffset(ProcessBytes);
        FRecivedBuffer.CheckCompactionMemory();
      end;
      
    end;
  end;

  TrySend();
end;

procedure TKDRecvAbleSocket.SetOnBinary(const Value: TKDSocketBinaryFrameEvent);
begin
  FOnBinary := Value;
end;

procedure TKDRecvAbleSocket.SetOnClose(const Value: TKDSocketCloseEvent);
begin
  FOnClose := Value;
end;

procedure TKDRecvAbleSocket.SetOnText(const Value: TKDSocketRecvTextEvent);
begin
  FOnText := Value;
end;

procedure TKDRecvAbleSocket.SetSendBufferSize(Size: Integer);
begin
  inherited;
  FSocketSendBufferSize := Size;
end;

procedure TKDRecvAbleSocket.TryParserWebSocketHandShark;
const 
  EndStrFlag : AnsiString = #13#10#13#10;
  WS_HKEY = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
var
  EndFlag : Integer;
  I , Size , EndFlagIndex , nPos  :Integer;
  PEndFlag : PByte;
  Context : AnsiString;
  ContextLenght:Integer;
  HttpHeader:TStringList;
  TempString , HttpKey,HttpValue:String;
  Connection : String;
  WebSocketVer : String;
  UpgradeType : String;
  WebSocketKey :String;
  ResultKey :String;
  SendStr:String;
  SendBytes:TBytes;
  KeyBytes:TBytes;
begin
   Size := FRecivedBuffer.Size;

  if Size < 4 then
    Exit;

    //1K的包握手还不完整 那么就是攻击 滚你吗的
  if Size > 1024 then
  begin
    Close(sceHandShareAttack,0);
    Exit;     
  end;
  
  Move(EndStrFlag[1],EndFlag,4);
  PEndFlag := FRecivedBuffer.Memory;
 
  EndFlagIndex := -1;
  I := 0; 
  while I <= Size - 4 do
  begin
    if PInteger(PEndFlag)^ = EndFlag then
    begin
      EndFlagIndex := I ;
      Break;
    end;
    Inc(PEndFlag);
    Inc(I);
  end;

  //没有找到说明封包还没到
  if EndFlagIndex = - 1 then
    Exit;

  ContextLenght := EndFlagIndex; 
    
  SetLength(Context,ContextLenght );

  Move(FRecivedBuffer.Memory^,Context[1],ContextLenght);

  HttpHeader := TStringList.Create;
  HttpHeader.Text := Context;
  for i := 1 to HttpHeader.Count - 1 do
  begin
    TempString := HttpHeader[i];
    nPos := Pos(':',TempString);
    if nPos > 0 then
    begin
      HttpKey := Copy(TempString,1,nPos - 1);
      HttpValue := Copy(TempString,nPos + 1,Length(TempString));
    end;
    HttpHeader[i] := Trim(LowerCase(HttpKey)) + '=' + Trim(HttpValue); 
  end;

  Connection := HttpHeader.Values['connection'];
  if LowerCase(Connection) <> 'upgrade' then
  begin
    Close(sceHandShark,0);
    Exit;
  end;

  WebSocketVer := HttpHeader.Values['Sec-WebSocket-Version'];
  if WebSocketVer <> '13' then
  begin
    Close(sceHandShark,0);
    Exit;  
  end;

  UpgradeType := HttpHeader.Values['Upgrade'];
  if LowerCase(UpgradeType) <> 'websocket' then
  begin
    Close(sceHandShark,0);
    Exit;  
  end;

  WebSocketKey := HttpHeader.Values['Sec-WebSocket-Key'] + WS_HKEY; 

  if Length(WebSocketKey) > 128 then
  begin
    Close(sceHandShareAttack,0);
    Exit;     
  end;

  KeyBytes := THashSHA1.GetHashBytes(WebSocketKey);
  
  ResultKey := TNetEncoding.Base64.EncodeBytesToString(KeyBytes);
  

  SendStr := 'HTTP/1.1 101 Switching Protocols' + #13#10 +
             'Upgrade: websocket' + #13#10 +
             'Connection: Upgrade' + #13#10 +
             'Sec-WebSocket-Accept: ' + ResultKey +  #13#10#13#10;
  SendBytes := TEncoding.UTF8.GetBytes(SendStr);  

  FSendBuffer.Append(@SendBytes[0],Length(SendBytes));          

  FIsHandSharked := True;

  FRecivedBuffer.Clear();
end;

function TKDRecvAbleSocket.TryRecv:Boolean;
var
  ErrorCode, nReadCount: Integer;
  nBuffSize: Cardinal;
  fdcloseset: TFDSet;
  fdexceptionset: TFDSet;
  TimereadVal: timeval;
  nRecved: Integer;
begin
  if _fd = INVALID_SOCKET then
    Exit(False);

  ErrorCode := ioctlsocket(_fd, FIONREAD, nBuffSize);
  if ErrorCode = NO_ERROR then
  begin
    if nBuffSize <= 0 then
      Exit(False);

    While (FRecivedBuffer.LeftSize < nBuffSize ) do
    begin
      FRecivedBuffer.GrowUp();
    end;

    nReadCount := WinSock2.recv(_fd , FRecivedBuffer.Memory^, nBuffSize, 0);

    //连接被关闭
    if nReadCount = 0 then
    begin
      Close(sceRead,0);
      Exit(False);
    end;

    if nReadCount = SOCKET_ERROR then
    begin
      ErrorCode := WSAGetLastError();
      if ErrorCode <> WSAEWOULDBLOCK then
      begin
        OnSocketError(ErrorCode);
        Close(sceRead,0);
      end;
      Exit(False);
    end
    else
    begin
      FRecivedBuffer.SizeAdd(nBuffSize);
      Exit(True);
    end;

  end
  else
  begin
    ErrorCode := WSAGetLastError();
    OnSocketError(ErrorCode);
    Exit(False);
  end;
end;

procedure TKDRecvAbleSocket.TrySend;
var
  I:Integer;
  SendSize : Integer;
begin
  if FSendBuffer.Size > 0 then
  begin
    SendSize := Min(FSendBuffer.Size,FSocketSendBufferSize);
    if Send(FSendBuffer.Memory,SendSize) = SendSize then
    begin
      FSendBuffer.ForwardOffset(SendSize);
    end;
    FSendBuffer.CheckCompactionMemory();
  end;
end;

initialization
  WSAStartup(MAKEWORD(2, 2), &wsaData);
finalization
  WSACleanup();
end.
