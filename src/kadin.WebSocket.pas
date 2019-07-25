unit kadin.WebSocket;

interface
  uses Classes,System.SysUtils,System.Hash,System.NetEncoding,System.Net.Socket;

const
  OPCODE_CONTINUE_FRAME = 0;
  OPCODE_TEXT_FRAME = 1;
  OPCODE_BINARY_FRAME = 2;
  OPCODE_CLOSE_FRAME = 8; 
  OPCODE_PING_FRAME = 9;
  OPCODE_PONG_FRAME = $A;
 
Type
  
(*
	fin :1;
	rsv1:1;
	rsv2:1;
	rsv3:1;
	opcode:4;  -----一个字节结束
	mask:1;
	payloadlen:7; ------两个字节结束
	
	maskingkey:可选 4字节
	extendpayloadlen: * 126 127 , 2byte ,8byte 	
*)  

  
  pTWebSocketFrame = ^TWebSocketFrame;
  TWebSocketFrame = record
    Opcode : Byte;
    PData : PByte;
    Len : Cardinal;
  end;

  //成功  数据不足  数据错误 需要关闭
  TParseWebSocketResult = (pwsSucess , pwsDataNotEngough,pwsDataError);

  //从一个流中解析一个websocket包 如果解析成功了 返回值是 整个包体的大小 否则 <= 0 是没有拿到一个包
 //ps 注意 这个是直接在Buf 上操作解包的 不会产生额外的内存 所以 外部释放数据应该小心注意。
 function UnPackWebSocketFrame(const Buf: Pointer; nLen: Integer;
  var frame: TWebSocketFrame):Integer;


 // opcode 对应的opcode
 // pdata DataLen  要打包的数据指针, 如果mask数据内容会被改变
 // mask 掩码 > 0 表示要掩码
 // pFrameHeader HeaderSize 同样这个函数不会出现任何的内存申请操作 所以传入的 pFrameHeader 应当>= 14 的长度指针 HeaderSize 为传入的长度  HeaderSize 这个长度会被改变后传递出来
 // 返回值: 0 成功。 -1: 传入的 FrameHeaderSize 太小 外部只要保证FrameHeaderSize >= 14 就绝对不会有这个问题  -2 : 传入的数据太大了。不能大于 2^31 - 14

 function PacketWebSocketFrame(opcode : Byte ;pData : PByte ; DataLen:Integer ; Mask : Integer ; pFrameHeader : PByte ; var FrameHeaderSize:Integer ):Integer;

 //从一段内存中 解析 websocket 握手包 返回值表示是否解析成功
 //如果成功 BufferLen 会被修改为实际的 大小 WebSocketParserHeader 为握手内容包  Response 为将要返回给客户端的握手内容

 function ParserWebSocketHandshake(PBuffer:Pointer;var BufferLen:Integer;out WebSocketParserHeader:TStringList;var Response:String):TParseWebSocketResult;

implementation

function UnPackWebSocketFrame(const Buf: Pointer; nLen: Integer;
  var frame: TWebSocketFrame):Integer;
var
	pProcessByte:PByte;
	HeaderData : Word;
	Opcode : Byte;
	Mask : Boolean;
	PayloadLen : Byte;
	HasExtPayLoadLen : Boolean;
	DataLen : Integer;
	MaskData : Array [0..3] of Byte;
  TempMaskData :array [0..3] of Byte;
	NeedLen : Integer;
	DataLen64 : Int64;
  I:Integer;
begin

	NeedLen := 2;
	
	//websocket 头至少是2字节如果不足2字节 那么再见
	if nLen < NeedLen then
	begin
	  Exit(0);
	end;

	HeaderData := PWord(Buf)^;
	pProcessByte := Buf;
	Opcode := pProcessByte^ and $F; 
	
	inc(pProcessByte);
	Mask := (pProcessByte^ and $80) <> 0;
	
	if Mask then
	begin
	  Inc(NeedLen,4);
	end;
	
	PayloadLen := (pProcessByte^ and $7F);
	
	DataLen := 0;
	HasExtPayLoadLen := False;
	if Payloadlen <= 125 then
	begin
		DataLen := Payloadlen;
	end else if Payloadlen = 126 then
	begin
		HasExtPayLoadLen := true;
		Inc(NeedLen,2);
	end
  else if Payloadlen = 127 then
	begin
		HasExtPayLoadLen := true;
		Inc(NeedLen,8);
	end;
	
	//达不到预期长度 再见
	if nLen < NeedLen then
	begin
	  Exit(0);
	end;

  inc(pProcessByte,1);
	if HasExtPayLoadLen then
	begin
		if (Payloadlen = 126) then
		begin	
			DataLen := PWord(pProcessByte)^;
			inc(pProcessByte,2);
		end else
		begin
			Move(pProcessByte^,DataLen64,8);
			inc(pProcessByte,8);
			
			//单个包 不能超过2G  超过我就炸了。 返回 - 1表示异常 请上层断开 清理掉缓冲区 14是最长的 frame header 是 14个字节
			if DataLen64 >= High(Integer) - 14 then
			begin
				Exit(-1);
			end else
			begin
				DataLen := DataLen64;
			end;
		end;
	end;
	
	Inc(NeedLen,DataLen);
	
	//达不到预期长度 再见
	if nLen < NeedLen then
	begin
	  Exit(0);
	end;
	
	frame.Opcode := Opcode;
	frame.pData := pProcessByte;
	frame.Len := DataLen;
	
	if Mask then
	begin
		Move(pProcessByte^,MaskData[0],4);
		Inc(pProcessByte,4);

    frame.pData := pProcessByte;
		for i := 0 to DataLen - 1 do
		begin
		  pProcessByte^ := (pProcessByte^) xor (MaskData[i mod 4]);
		  Inc(pProcessByte);
		end;	
	end;
	
	Result := NeedLen;
end;

function PacketWebSocketFrame(opcode : Byte ;pData : PByte ; DataLen:Integer ; Mask : Integer ; pFrameHeader : PByte ; var FrameHeaderSize:Integer ):Integer;
var
  HasMaskByte:Byte;
  Len : Integer;
  MaskData : Array[0..3] of Byte;
  I:Integer;
begin

	if FrameHeaderSize < 14 then
	begin
		Result := -1;
		Exit;
	end;
	
	if (DataLen < 0) or  (DataLen > High(Integer) - 14) then
	begin
		Result := -2;
		Exit;
	end;
	
	pFrameHeader^ := $80 or (opcode and $F); //表示这个包不是断包 通常都是这样 
	Inc(pFrameHeader);
	if (Mask > 0) then
	  HasMaskByte := $80
	else
	  HasMaskByte := 0;
	
	FrameHeaderSize := 2; //websocket frame 最短要2个字节
	
	if DataLen <= 125 then
	begin
		pFrameHeader^ := DataLen or HasMaskByte;
	end else if DataLen <= 65535 then
	begin
		pFrameHeader^ := 126 or HasMaskByte;
		Inc(pFrameHeader);
		Move(DataLen,pFrameHeader^,2);
		Inc(pFrameHeader,2);
		Inc(FrameHeaderSize,2);	
	end else 
	begin
		pFrameHeader^ := 127 or HasMaskByte;
		Inc(pFrameHeader);
		Move(DataLen,pFrameHeader^,4);
		Inc(pFrameHeader,8);
		Inc(FrameHeaderSize,8);			
	end;
	
	if ( Mask > 0 ) then
	begin
		Move(Mask,pFrameHeader^,4);	
		Inc(FrameHeaderSize,4);		
		if DataLen > 0 then
		begin
			for i := 0 to DataLen - 1 do
			begin
				pFrameHeader^ := (pFrameHeader^) xor (MaskData[i mod 4]);
				inc(pFrameHeader);
			end;
		end
	end;
	
	Result := 0;
end;


function ParserWebSocketHandshake(PBuffer:Pointer;var BufferLen:Integer;out WebSocketParserHeader:TStringList;var Response:String):TParseWebSocketResult;
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
   Size := BufferLen;

  if Size < 4 then
    Exit(pwsDataNotEngough);


  if Size > 1024 then
    Exit(pwsDataError);

  Move(EndStrFlag[1],EndFlag,4);
  PEndFlag := PBuffer;

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
     Exit(pwsDataError);


  ContextLenght := EndFlagIndex;

  SetLength(Context,ContextLenght );

  Move(PBuffer^,Context[1],ContextLenght);

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
    Exit(pwsDataError);
  end;

  WebSocketVer := HttpHeader.Values['Sec-WebSocket-Version'];
  if WebSocketVer <> '13' then
  begin
    Exit(pwsDataError);
  end;

  UpgradeType := HttpHeader.Values['Upgrade'];
  if LowerCase(UpgradeType) <> 'websocket' then
  begin
    Exit(pwsDataError);
  end;

  WebSocketKey := HttpHeader.Values['Sec-WebSocket-Key'] + WS_HKEY;

  if Length(WebSocketKey) > 128 then
  begin
    Exit(pwsDataError);
  end;

  KeyBytes := THashSHA1.GetHashBytes(WebSocketKey);

  ResultKey := TNetEncoding.Base64.EncodeBytesToString(KeyBytes);


  Response := 'HTTP/1.1 101 Switching Protocols' + #13#10 +
             'Upgrade: websocket' + #13#10 +
             'Connection: Upgrade' + #13#10 +
             'Sec-WebSocket-Accept: ' + ResultKey +  #13#10#13#10;

  Result := pwsSucess;
end;

end.
