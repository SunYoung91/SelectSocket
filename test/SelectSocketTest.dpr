program SelectSocketTest;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  ScktComp,
  kadin.ClientSocket in '..\src\kadin.ClientSocket.pas',
  kadin.SocketBase in '..\src\kadin.SocketBase.pas',
  kadin.ServerSocket in '..\src\kadin.ServerSocket.pas';

var
  Socket : TClientSocket;
begin
  try
    Socket := TClientSocket.Create(nil);
    Socket.Host := '127.0.0.1';
    Socket.Port := 6669;
    Socket.Active := True;
    { TODO -oUser -cConsole Main : Insert code here }
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
