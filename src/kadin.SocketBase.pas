unit kadin.SocketBase;

interface
uses
  WinSock2,SysUtils;
Type
  ESelectSocketError = class(Exception)
    ErrorCode : Integer;
  end;

  //注意 Property 可能会抛异常 函数类的不会抛异常
  TKDSocket = class
  private
    function GetRecvbBufferSize():Integer;
    function GetSendBufferSize():Integer;
    procedure SetRecvBufferSize(Size:Integer);
    procedure SetSendBufferSize(Size:Integer);
    procedure SetBlockMode(isBlock:Boolean);
  protected
     _fd : TSocket;
     _addr_in : TSockAddrIn;
     _isBlockMode: Boolean;
     procedure OnSocketConnected();virtual;
     procedure OnSocketError(ErrorCode:Integer);virtual;
     procedure OnSocketClose();virtual;
  public
    constructor Create();
    constructor CreateBySocket(Socket:TSocket);

    function Close():Boolean;
    function Send(pData:PByte;Size:Integer):Integer;
    function Recv(pData:PByte;Size:Integer):Integer;
    function Connect(const IP:String;Port:Integer):Integer;
    function Bind(const IP:string;Port:Integer):Integer;
    function Accept(var fd:TSocket ; var addr_in:TSockAddrIn ):Integer;

    property SendBufferSize : Integer Read GetSendBufferSize write SetSendBufferSize;
    property RecvBufferSize : Integer read GetRecvbBufferSize write SetRecvBufferSize;
    property BlockMode : Boolean read _isBlockMode write SetBlockMode;
  end;

implementation

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
    _addr_in.sin_addr.S_addr := PCardinal(pHost.h_addr_list)^;
    _addr_in.sin_family := PF_INET;
    Move(_addr_in, SocktAddr, SizeOf(SocktAddr));
    Result := WinSock2.bind(_fd,SocktAddr,SizeOf(SocktAddr));
  end else
  begin
    Result := WSAGetLastError();
  end;
end;

function TKDSocket.Close():Boolean;
begin
	if ( _fd <> INVALID_SOCKET ) then
  begin
    closesocket( _fd );
		_fd := INVALID_SOCKET;
    Result := True;
    OnSocketClose();
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
  Close();
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
    Close();
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

procedure TKDSocket.OnSocketClose;
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
    Close();
    Result := 0;
    Exit;
  end;

  if Result = SOCKET_ERROR then
  begin
    Result := WSAGetLastError();
    if Result <> WSAEWOULDBLOCK then
    begin
      OnSocketError(Result);
      Close();
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
      Close();
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

end.
