unit WebSocketServer;

interface
  uses kadin.ServerSocket,kadin.SocketBase,System.Classes;
type
  TWebSocketServer = class(TKDServerSocket)
  private
    procedure RecvOnText (Sender:TKDRecvAbleSocket ; const Text:String);
  public
    constructor Create();

  end;
procedure Run();
implementation
var
  Server:TKDServerSocket;
procedure Run();
begin
  Server := TKDServerSocket.Create;
  if Server.Bind('0.0.0.0',9000) = 0 then
  begin
    while True do
    begin
      TThread.Sleep(1);
      Server.Run();
    end;
  end;
end;

{ TWebSocketServer }

constructor TWebSocketServer.Create;
begin
  inherited;
  //Self.OnText := RecvOnText ;
end;

procedure TWebSocketServer.RecvOnText(Sender: TKDRecvAbleSocket;
  const Text: String);
begin

end;

end.
