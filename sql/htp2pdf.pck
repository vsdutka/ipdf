create or replace package htp2pdf is

  -- Author  : VSDUTKA
  -- Created : 27.07.2015 10:19:57
  -- Purpose : 
  
  -- Public type declarations
  type t_file is record (
    file_body          clob,
    file_orientation   char(1),
    page_size          varchar2(20),
    margin_left        number(12, 0),
    margin_right       number(12, 0),
    margin_top         number(12, 0),
    margin_bottom      number(12, 0),
    margin_header      number(12, 0),
    margin_footer      number(12, 0)
  );
  type t_files is table of t_file index by binary_integer;
  
  -- Public constant declarations
  -- Public variable declarations
  -- Public function and procedure declarations
  procedure htp2file
    (
      afiles             in out t_files
      ,aorientation      in char
      ,apage_size         in varchar2
      ,amargin_left      in number
      ,amargin_right     in number
      ,amargin_top       in number
      ,amargin_bottom    in number
      /*,amargin_header    in number
      ,amargin_footer    in number*/
    );
    
  procedure htp2file
    (
      aorientation      in char
      ,apage_size         in varchar2
      ,amargin_left      in number
      ,amargin_right     in number
      ,amargin_top       in number
      ,amargin_bottom    in number
      /*,amargin_header    in number
      ,amargin_footer    in number*/
    );
    
  procedure htp2pdf(afilename in varchar2, afiles in t_files);
  procedure htp2pdf(afilename in varchar2);

  procedure set_collect(acollect in boolean);
end htp2pdf;
/
create or replace package body htp2pdf is
  -- Function and procedure implementations
  gfiles t_files;
  gcollect boolean := false;

  procedure set_collect(acollect in boolean)
  is
  begin
    gcollect := acollect;
  end;
  
  procedure htp2file 
    (
      afiles             in out t_files
      ,aorientation      in char
      ,apage_size         in varchar2
      ,amargin_left      in number
      ,amargin_right     in number
      ,amargin_top       in number
      ,amargin_bottom    in number
      /*,amargin_header    in number
      ,amargin_footer    in number*/
    )
  is
    CURR_LINE_NUM INTEGER;
    L_LINES_Q     INTEGER := 2147483646;
    lines         sys.htp.htbuf_arr;
    NL_CHAR       constant varchar2(10) := chr(10);
    
    iLast         integer := nvl(afiles.last(),0) + 1;
    image_path    varchar2(1024);
  begin
    if not gcollect then
      return;
    end if;
    
    afiles(iLast).file_orientation := aorientation;
    afiles(iLast).page_size        := apage_size;
    afiles(iLast).margin_left      := amargin_left;
    afiles(iLast).margin_right     := amargin_right;
    afiles(iLast).margin_top       := amargin_top;
    afiles(iLast).margin_bottom    := amargin_bottom;
    /*afiles(iLast).margin_header    := amargin_header;
    afiles(iLast).margin_footer    := amargin_footer;*/
    

    image_path := owa_util.get_cgi_env('SERVER_NAME');
    if instr(image_path, ':') = 0 then
      if length(owa_util.get_cgi_env('SERVER_PORT')) > 0 then
        image_path := image_path || ':' || owa_util.get_cgi_env('SERVER_PORT');
      end if;
    end if; 
    if owa_util.get_cgi_env('HTTPS') = 'Y' then
      image_path := 'https://' || image_path;
    else
      image_path := 'http://' || image_path;
    end if;
    --

    /* ------------------- */
    sys.htp.flush;
    sys.htp.get_page(lines, L_LINES_Q);
    CURR_LINE_NUM := 0;

    if L_LINES_Q = 0 then
      L_LINES_Q := 1;
      lines(1) := '0';
    end if;

    WHILE CURR_LINE_NUM <= L_LINES_Q + 1 loop
      CURR_LINE_NUM := CURR_LINE_NUM + 1;
      begin
        if lines(CURR_LINE_NUM)=NL_CHAR then
          -- Нашли конец заголовков
          exit;
        end if;
      exception
        when NO_DATA_FOUND then
          null;
      end;
    end loop;

    afiles(iLast).file_body := '';
    WHILE CURR_LINE_NUM <= L_LINES_Q + 1 loop
      CURR_LINE_NUM := CURR_LINE_NUM + 1;
      begin
        
        afiles(iLast).file_body := afiles(iLast).file_body || replace(lines(CURR_LINE_NUM), '<img src="/', '<img src="'||image_path||'/');
      exception
        when NO_DATA_FOUND then
          null;
      end;
    end loop;
    afiles(iLast).file_body := trim(afiles(iLast).file_body);
    if dbms_lob.getlength(afiles(iLast).file_body)=0 then
      raise_application_error(-20000, 'Empty body file');
    end if;
    sys.htp.init;
    a.htp.init;
  end;
  
  procedure htp2file 
    (
      aorientation      in char
      ,apage_size         in varchar2
      ,amargin_left      in number
      ,amargin_right     in number
      ,amargin_top       in number
      ,amargin_bottom    in number
      /*,amargin_header    in number
      ,amargin_footer    in number*/
    )
  is
  begin
    htp2file 
      (
        gfiles             
        ,aorientation      
        ,apage_size        
        ,amargin_left      
        ,amargin_right     
        ,amargin_top       
        ,amargin_bottom    
        /*,amargin_header
        ,amargin_footer*/
      );
  end;
  
  procedure htp2pdf(afilename in varchar2, afiles in t_files)
  is
    type tbodies is table of raw(32767) index by binary_integer;
    req           Utl_Http.Req;
    resp          Utl_Http.Resp;
    msg_multipart clob;
    parts         tbodies;
    l_body_length NUMBER := 0;
    resp_data     BLOB;
    crlf          VARCHAR2(2) := CHR(13) || CHR(10);
    j             number := 0;
    boundary  constant varchar2(1000) := '----WebKitFormBoundaryNCqTXysxebO3VRTo';
  BEGIN
    if not gcollect then
      return;
    end if;
    
    for i in afiles.first()..afiles.last() loop
      if dbms_lob.getlength(afiles(i).file_body) > 0 then
        j := j + 1;
        --Creating the message, detecting its size...
        msg_multipart := '--' || boundary || crlf;
        msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="file"; filename="'||i||'.html"' || crlf;
        msg_multipart := msg_multipart || 'Content-Type: text/html' || crlf;
        msg_multipart := msg_multipart || crlf;

        msg_multipart := msg_multipart || afiles(i).file_body;
        msg_multipart := msg_multipart || crlf;
        
        dbms_output.put_line('-----------------------------------------');
        dbms_output.put_line( afiles(i).file_body);

        msg_multipart := msg_multipart || '--' || boundary || crlf;
        msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="orientation"' || crlf;
        msg_multipart := msg_multipart || crlf;
        msg_multipart := msg_multipart || afiles(i).file_orientation ;
        msg_multipart := msg_multipart || crlf;
        
        msg_multipart := msg_multipart || '--' || boundary || crlf;
        msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="page_size"' || crlf;
        msg_multipart := msg_multipart || crlf;
        msg_multipart := msg_multipart || afiles(i).page_size ;
        msg_multipart := msg_multipart || crlf;
        
        msg_multipart := msg_multipart || '--' || boundary || crlf;
        msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="margin-left"' || crlf;
        msg_multipart := msg_multipart || crlf;
        msg_multipart := msg_multipart || afiles(i).margin_left ;
        msg_multipart := msg_multipart || crlf;
        
        msg_multipart := msg_multipart || '--' || boundary || crlf;
        msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="margin-right"' || crlf;
        msg_multipart := msg_multipart || crlf;
        msg_multipart := msg_multipart || afiles(i).margin_right ;
        msg_multipart := msg_multipart || crlf;
        
        msg_multipart := msg_multipart || '--' || boundary || crlf;
        msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="margin-top"' || crlf;
        msg_multipart := msg_multipart || crlf;
        msg_multipart := msg_multipart || afiles(i).margin_top ;
        msg_multipart := msg_multipart || crlf;
        
        msg_multipart := msg_multipart || '--' || boundary || crlf;
        msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="margin-bottom"' || crlf;
        msg_multipart := msg_multipart || crlf;
        msg_multipart := msg_multipart || afiles(i).margin_bottom ;
        msg_multipart := msg_multipart || crlf;
        
        /*msg_multipart := msg_multipart || '--' || boundary || crlf;
        msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="MARGIN_HEADER"' || crlf;
        msg_multipart := msg_multipart || crlf;
        msg_multipart := msg_multipart || afiles(i).margin_header ;
        msg_multipart := msg_multipart || crlf;
        
        msg_multipart := msg_multipart || '--' || boundary || crlf;
        msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="MARGIN_FOOTER"' || crlf;
        msg_multipart := msg_multipart || crlf;
        msg_multipart := msg_multipart || afiles(i).margin_footer ;
        msg_multipart := msg_multipart || crlf;*/
        parts(j) := utl_raw.cast_to_raw(msg_multipart);
        l_body_length := l_body_length + utl_raw.length(parts(j));
      end if;
    end loop;
    msg_multipart := '--' || boundary || crlf;
    msg_multipart := msg_multipart || 'Content-Disposition: form-data; name="double_side"' || crlf;
    msg_multipart := msg_multipart || crlf;
    msg_multipart := msg_multipart || 'Y' ;
    msg_multipart := msg_multipart || crlf;
    msg_multipart := msg_multipart || '--' || boundary || '--' || crlf;
    j := j + 1;
    parts(j) := utl_raw.cast_to_raw(msg_multipart);

    l_body_length := l_body_length + utl_raw.length(parts(j));

    -- request that exceptions are raised for error Status Codes */
    Utl_Http.Set_Response_Error_Check(enable => false);
    -- allow testing for exceptions like Utl_Http.Http_Server_Error */
    Utl_Http.Set_Detailed_Excp_Support(enable => true);
    Utl_Http.set_persistent_conn_support(true);

    -- open the HTTP request
    req := Utl_Http.Begin_Request('http://dp-asw4:17000/', 'POST', 'HTTP/1.1');
    utl_http.set_transfer_timeout(req, 30);

    -- set header

    Utl_Http.Set_Header(r => req, name => 'Content-Length', value => TO_CHAR(l_body_length));
    Utl_Http.Set_Header(r => req, name => 'Content-Type', value => 'multipart/form-data; boundary=' || boundary);

    --Creating the message...
    for i in parts.first()..parts.last()
    loop
      utl_http.write_raw(req, parts(i));
    end loop;
     
    
/*    dbms_output.put_line('============ Request ============');
    dbms_output.put_line('http_req.url = "' || req.url || '"');
    dbms_output.put_line('http_req.method = "' || req.method || '"');
    dbms_output.put_line('http_req.http_version = "' || req.http_version || '"');
    dbms_output.put_line('Content-Length = "' || l_multipart || '"');
    dbms_output.put_line('Body = "' || msg_multipart || '"');
    
    dbms_output.put_line('=================================');*/

    -- receive the response
    resp := Utl_Http.get_response(req);

    declare
      resp_chunk raw(32767);
      chunk_size constant integer := 32767;
    begin
      dbms_lob.createtemporary(resp_data, false);
      LOOP
        begin
          utl_http.read_raw(resp, resp_chunk, chunk_size);
          dbms_lob.writeappend(resp_data, utl_raw.length(resp_chunk), resp_chunk);
        exception
          when Utl_Http.End_Of_Body then
            utl_http.end_response(resp);
            exit;
        end;
      END LOOP;
    end;

/*    dbms_output.put_line('============ Response ===========');
    dbms_output.put_line('http_resp.status_code: "' || resp.status_code || '"');
    dbms_output.put_line('http_resp.reason_phrase: "' || resp.reason_phrase || '"');
    dbms_output.put_line('http_resp.http_version: "' || resp.http_version || '"');
    dbms_output.put_line('http_resp.content_length: "' || dbms_lob.getlength(resp_data) || '"');
    dbms_output.put_line('http_resp.content: "' || utl_raw.cast_to_varchar2(dbms_lob.substr(resp_data, 4000)) || '"');
    dbms_output.put_line('=================================');*/
    
    if resp.status_code = utl_http.HTTP_OK then 
      htp.set_ContentType('application/pdf');
      htp.add_CustomHeader('Content-disposition: inline; filename="'||afilename||'"');
      wpg_docload.download_file(resp_data);
    else
      raise_application_error(-20000, utl_raw.cast_to_varchar2(dbms_lob.substr(resp_data, 4000)));
    end if;
  exception
    when utl_http.http_server_error then
      htp.prn(utl_http.get_detailed_sqlerrm);
  end;

  procedure htp2pdf(afilename in varchar2)
  is
  begin
    htp2pdf(afilename, gfiles);
    gfiles.delete();
  end;

end htp2pdf;
/
