program SelectSocketTest;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  ScktComp,
  kadin.ClientSocket in '..\src\kadin.ClientSocket.pas',
  kadin.SocketBase in '..\src\kadin.SocketBase.pas',
  kadin.ServerSocket in '..\src\kadin.ServerSocket.pas',
  uMemBuffer in '..\src\uMemBuffer.pas',
  uSyncObj in '..\src\uSyncObj.pas',
  kadin.WebSocket in '..\src\kadin.WebSocket.pas',
  WebSocketServer in 'WebSocketServer.pas';

begin
  try
    WebSocketServer.Run();
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
