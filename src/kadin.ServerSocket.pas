unit kadin.ServerSocket;

interface
uses kadin.SocketBase,System.Generics.Collections,Winapi.Winsock2;
Type

  //连接上服务器的Socket  不可手动建立
  TKDServerClientSocket = class(TKDRecvAbleSocket)
  public
    ServerSocketIndex : Cardinal; //在ServerSocket 中的下标
  private
    procedure SetSocketData(SocketHandle:TSocket ;AddrIn : TSockAddrIn);
  end;

  //服务端类
  TKDServerSocket = class(TKDSocket)
  private
    FClients : TList<TKDServerClientSocket>;
    function NewClientSocket(SocketHandle:TSocket ;AddrIn : TSockAddrIn):TKDServerClientSocket;
    procedure TryAccept();
    procedure TryRecv();
    procedure TrySend();
  public
    procedure Run();
  end;

implementation

{ TKDServerClientSocket }

procedure TKDServerClientSocket.SetSocketData(SocketHandle: TSocket;
  AddrIn: TSockAddrIn);
begin
  _fd := SocketHandle;
  _addr_in := AddrIn;
end;

{ TKDServerSocket }

function TKDServerSocket.NewClientSocket(SocketHandle:TSocket ;AddrIn : TSockAddrIn):TKDServerClientSocket;
var
  I:Cardinal;
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
begin
  TryAccept();
  TryRecv();
  TrySend();
end;

procedure TKDServerSocket.TryAccept;
var
  ErrorCode:Integer;
  SocketHandle:TSocket;
  AddrIn:TSockAddrIn;
begin
  ErrorCode := Accept(SocketHandle,AddrIn);
  //新的Socket 来了
  if ErrorCode > 0 then
  begin
    NewClientSocket(SocketHandle,AddrIn);
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
