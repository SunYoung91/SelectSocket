unit kadin.ClientSocket;

interface
uses
  WinSock2,Windows,kadin.SocketBase,uMemBuffer;
type
  //非线程安全的客户端连接类
  TKDClientSocket = class(TKDRecvAbleSocket)


  end;
implementation

{ TKDClientSocket }


end.
