unit kadin.ClientSocket;

interface
uses
  WinSock2,Windows,kadin.SocketBase,uMemBuffer;
type
  //非线程安全的客户端连接类
  TKDClientSocket = class(TKDSocket)
  private
    FRecivedBuffer : TuMemBuffer;  //待处理的内容
    FSendBuffer : TuMemBuffer;     //待发送的内容
    FNewDataRead : Boolean;
  protected
    procedure TryRecv();
    procedure TrySend();
  public
    procedure Execute(); // 外部调用执行Socket 各种事件
  end;
implementation

{ TKDClientSocket }

procedure TKDClientSocket.Execute;
begin

end;

procedure TKDClientSocket.TryRecv;
var
  ErrorCode, nReadCount: Integer;
  nBuffSize: Cardinal;
  fdreadset: TFDSet;
  fdcloseset: TFDSet;
  fdexceptionset: TFDSet;
  TimereadVal: timeval;
  nRecved: Integer;
begin
  if _fd = INVALID_SOCKET then
    Exit;

  ErrorCode := ioctlsocket(_fd, FIONREAD, nBuffSize);
  if ErrorCode = NO_ERROR then
  begin
    if nBuffSize <= 0 then
      Exit;

    While (FRecivedBuffer.LeftSize < nBuffSize ) do
    begin
      FRecivedBuffer.GrowUp();
    end;

    nReadCount := WinSock2.recv(_fd , FRecivedBuffer.Memory^, nBuffSize, 0);

    //连接被关闭
    if nReadCount = 0 then
    begin
      Close();
      Exit;
    end;

    if nReadCount = SOCKET_ERROR then
    begin
      ErrorCode := WSAGetLastError();
      if ErrorCode <> WSAEWOULDBLOCK then
      begin
        OnSocketError(ErrorCode);
        Close();
      end;
      Exit;
    end
    else
    begin
      FRecivedBuffer.SizeAdd(nBuffSize);
      FNewDataRead := True;
    end;

  end
  else
  begin
    ErrorCode := WSAGetLastError();
    OnSocketError(ErrorCode)
    Exit;
  end;
end;

procedure TKDClientSocket.TrySend;
begin
  if FSendBuffer.Size > 0 then
  begin

  end;
end;

end.
