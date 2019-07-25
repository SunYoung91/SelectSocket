unit kadin.ServerSocket;

interface
uses kadin.SocketBase,System.Generics.Collections,Winapi.Winsock2;
Type

  //连接上服务器的Socket  不可手动建立
  TKDServerClientSocket = class(TKDRecvAbleSocket)
  public
    ServerSocketIndex : Integer; //在ServerSocket 中的下标
  private
    procedure SetSocketData(SocketHandle:TSocket ;AddrIn : TSockAddrIn);
  end;

  TOnClientConnect = procedure (Socket: TKDSocket);
  TOnClientAccept = procedure (const IP:string ; var Accept:Boolean);
  TOnClientDataRecv = procedure (Socket : TKDSocket; PData:Pointer ; DataLen:Integer);
  TOnClientClose = procedure(Socket:TKDSocket ; ErrorCode:Integer);
  //服务端类
  TKDServerSocket = class(TKDSocket)
  private
    FClients : TList<TKDServerClientSocket>;
    FOnClientConnect : TOnClientConnect;
    FOnClientAccept : TOnClientAccept;
    FOnClientDataRecv : TOnClientDataRecv;
    FOnClientClose : TOnClientClose;
    function NewClientSocket(SocketHandle:TSocket ;AddrIn : TSockAddrIn):TKDServerClientSocket;
    procedure TryAccept();
    procedure TryRecv();
    procedure TrySend();
  public
    constructor Create();
    procedure Run();
    property OnClientConnect:TOnClientConnect read FOnClientConnect write FOnClientConnect;
    property OnClientAccept : TOnClientAccept read FOnClientAccept Write FOnClientAccept;
    property OnClientDataRecv : TOnClientDataRecv read FOnClientDataRecv write FOnClientDataRecv;
    Property OnClientClose : TOnClientClose read FOnClientClose write FOnClientClose;
  end;

implementation

{ TKDServerClientSocket }

procedure TKDServerClientSocket.SetSocketData(SocketHandle: TSocket;
  AddrIn: TSockAddrIn);
begin
  _fd := SocketHandle;
  _addr_in := AddrIn;
  FSocketSendBufferSize := GetSendBufferSize();
end;

{ TKDServerSocket }

constructor TKDServerSocket.Create;
begin
  inherited;
  FClients := TList<TKDServerClientSocket>.Create;
end;

function TKDServerSocket.NewClientSocket(SocketHandle:TSocket ;AddrIn : TSockAddrIn):TKDServerClientSocket;
var
  I:Integer;
begin
  for i := 0 to FClients.Count - 1 do
  begin
    if FClients[i].ServerSocketIndex = 0 then
    begin
      Result := FClients[i];
      FClients[i].ServerSocketIndex := i;
      FClients[i].SetSocketData(SocketHandle,AddrIn);
      Exit;
    end;
  end;

  Result := TKDServerClientSocket.Create();
  Result.ServerSocketIndex := Cardinal(FClients.Add(Result));
  Result.SetSocketData(SocketHandle,AddrIn);

end;

procedure TKDServerSocket.Run;
var
  I:Integer;
begin
  TryAccept();
  //TryRecv();
  //TrySend();

  for I := 0 to FClients.Count - 1 do
  begin
    if FClients[i].ServerSocketIndex <> -1 then
    begin
      FClients[i].Run;
    end;
  end;
end;

procedure TKDServerSocket.TryAccept;
var
  ErrorCode:Integer;
  SocketHandle:TSocket;
  AddrIn:TSockAddrIn;
  CanAccept :Boolean;
  IP:String;
begin
  ErrorCode := Accept(SocketHandle,AddrIn);
  //新的Socket 来了
  if ErrorCode = 0 then
  begin
    CanAccept := True;
    if Assigned(FOnClientAccept) then
    begin
      FOnClientAccept(IP,CanAccept);
      if CanAccept then
        NewClientSocket(SocketHandle,AddrIn)
      else
        Winapi.Winsock2.closesocket(SocketHandle);
    end else
    begin
      NewClientSocket(SocketHandle,AddrIn);
    end;
  end;
end;

procedure TKDServerSocket.TryRecv;
var
  I:Integer;
begin
  for I := 0 to FClients.Count do
  begin
    if FClients[i].ServerSocketIndex <> 0 then
    begin
      FClients[i].TryRecv();
    end;
  end;
end;

procedure TKDServerSocket.TrySend;
var
  I:Integer;
begin
  for I := 0 to FClients.Count do
  begin
    if FClients[i].ServerSocketIndex <> 0 then
    begin
      FClients[i].TrySend();
    end;
  end;
end;

end.
