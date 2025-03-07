Program HelloWorld;

{$MODE ObjFPC}

Uses
  CThreads,
  Sockets,
  BaseUnix,
  SysUtils,
  Classes;

Const
  ServerPort=8080;
  BufferSize=4096;
  RootDir='./www';

Type
  TClientHandler=class(TThread)
  Private
    ClientSocket:LongInt;
  Protected
    Procedure Execute;override;
    Procedure HandleRequest;
  Public
    Constructor Create(AClientSocket:LongInt);
  End;

Constructor TClientHandler.Create(AClientSocket:LongInt);
Begin
  Inherited Create(False);
  ClientSocket:=AClientSocket;
  FreeOnTerminate:=True;
End;

Procedure TClientHandler.Execute;
Begin
  HandleRequest;
  FpClose(ClientSocket);
End;

Procedure TClientHandler.HandleRequest;
Var
  Buffer:array[1..BufferSize] Of Byte;
  ReceivedBytes:LongInt;
  Request,FilePath,FullPath:String;
  FileStream:TFileStream;
  ResponseHeader:String;

  Function GetContentType(Const FileExt:String):String;
  Begin
    Case LowerCase(FileExt) Of
      '.html', '.htm':Result:='text/html';
      '.css':Result:='text/css';
      '.js':Result:='application/javascript';
      '.png':Result:='image/png';
      '.jpg','.jpeg':Result:='image/jpeg';
      '.gif':Result:='image/gif';
      '.svg':Result:='image/svg+xml';
      '.ico':Result:='image/x-icon';
      '.json':Result:='application/json';
      '.txt':Result:='text/plain';
      Else Result:='application/octet-stream';
    End;
  End;

Begin
  FillChar(Buffer,BufferSize,0);
  ReceivedBytes:=FpRecv(ClientSocket,@Buffer,BufferSize,0);

  If ReceivedBytes>0 Then
  Begin
    Request:=String(PAnsiChar(@Buffer));

    If Pos('GET ',Request)=1 Then
    Begin
      FilePath:=Copy(Request,5,Pos(' HTTP/',Request)-5);
      If FilePath='/' Then
        FilePath:='/index.html';

      FullPath:=ExpandFileName(RootDir+FilePath);

      If FileExists(FullPath) And (Pos(ExpandFileName(RootDir),FullPath)=1) Then
      Begin
        FileStream:=TFileStream.Create(FullPath,FmOpenRead Or FmShareDenyWrite);
        Try
          ResponseHeader:='HTTP/1.1 200 OK'+sLineBreak+
                          'Content-Type: '+GetContentType(ExtractFileExt(FilePath))+SLineBreak+
                          'Content-Length: '+IntToStr(FileStream.Size)+SLineBreak+
                          'Connection: close'+SLineBreak+SLineBreak;
          FpSend(ClientSocket,@ResponseHeader[1],Length(ResponseHeader),0);
          While FileStream.Position<FileStream.Size Do
          Begin
            FileStream.Read(Buffer,BufferSize);
            FpSend(ClientSocket,@Buffer,BufferSize,0);
          End;
        Finally
          FileStream.Free;
        End;
      End
      Else
      Begin
        ResponseHeader:='HTTP/1.1 404 Not Found'+SLineBreak+
                        'Content-Type: text/html'+SLineBreak+
                        'Connection: close'+SLineBreak+SLineBreak+
                        '<html><body><h1>404 Not Found</h1></body></html>';
        FpSend(ClientSocket,@ResponseHeader[1],Length(ResponseHeader),0);
      End;
    End;
  End;
End;

Var
  ServerSocket,ClientSocket:LongInt;
  Address:TInetSockAddr;
  AddrLen:LongInt;

Begin
  ServerSocket:=FpSocket(AF_INET,SOCK_STREAM,0);
  If ServerSocket=-1 Then
  Begin
    WriteLn('Error: Unable to create socket.');
    Exit;
  End;

  Address.sin_family:=AF_INET;
  Address.sin_port:=htons(ServerPort);
  Address.sin_addr.s_addr:=htonl(INADDR_ANY);

  If FpBind(ServerSocket,@Address,SizeOf(Address))=-1 Then
  Begin
    WriteLn('Error: Unable to bind socket.');
    FpClose(ServerSocket);
    Exit;
  End;

  If FpListen(ServerSocket,10)=-1 Then
  Begin
    WriteLn('Error: Unable to listen on socket.');
    FpClose(ServerSocket);
    Exit;
  End;

  WriteLn('Server running on port ',ServerPort,'...');
  
  AddrLen:=SizeOf(Address);
  While True Do
  Begin
    ClientSocket:=FpAccept(ServerSocket,@Address,@AddrLen);
    If ClientSocket<>-1 Then
      TClientHandler.Create(ClientSocket);
  End;

  FpClose(ServerSocket);
End.
