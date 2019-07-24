unit kadin.WebSocket;

interface

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
	
	if HasExtPayLoadLen then
	begin
		inc(pProcessByte,1);
		
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
		Move(MaskData[0],pProcessByte^,4);
		Inc(pProcessByte,4);
			
		for i := 0 to DataLen - 1 do
		begin
		  pProcessByte^ := (pProcessByte^) xor (MaskData[i mod 4]);
		  Inc(pProcessByte);
		end;	
	end;
	
	Result := DataLen;	
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

end.
