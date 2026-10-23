#requires -Version 5.1
# 仅监听回环地址，按相对路径返回指定数据目录中的 JSON；无写入 API。
param([Parameter(Mandatory=$true)][string]$Root,[ValidateRange(1024,65535)][int]$Port=8080)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$rootPath=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
if(!(Test-Path -LiteralPath $rootPath -PathType Container)){throw 'JSON 根目录不存在。'}
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$Port)
try{
    $listener.Start();Write-Output "Mock：http://127.0.0.1:$Port/；仅提供 GET JSON。"
    while($true){
        $client=$listener.AcceptTcpClient();$client.ReceiveTimeout=5000;$client.SendTimeout=5000
        try{
            $stream=$client.GetStream();$reader=New-Object IO.StreamReader($stream,[Text.Encoding]::ASCII,$false,4096,$true)
            $line=$reader.ReadLine();$headerCount=0
            while(($header=$reader.ReadLine()) -ne ''){if($null -eq $header -or ++$headerCount -gt 100){throw '无效请求。'}}
            $status='200 OK';$type='application/json; charset=utf-8';$body=''
            if($line -notmatch '^GET (/[^ ]*) HTTP/1\.[01]$'){$status='405 Method Not Allowed';$body='{"error":"GET only"}'}
            else{
                $requestPath=[Uri]::UnescapeDataString(($Matches[1] -split '\?')[0])
                if($requestPath -eq '/'){
                    $names=@(Get-ChildItem -LiteralPath $rootPath -File -Filter '*.json'|Where-Object{!($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}|ForEach-Object{$_.Name})
                    $body=ConvertTo-Json -InputObject $names
                }else{
                    $relative=$requestPath.TrimStart('/').Replace('/',[IO.Path]::DirectorySeparatorChar)
                    $path=[IO.Path]::GetFullPath((Join-Path $rootPath $relative))
                    if(!$path.StartsWith($rootPath,[StringComparison]::OrdinalIgnoreCase)-or [IO.Path]::GetExtension($path) -ine '.json'){$status='403 Forbidden';$body='{"error":"Forbidden"}'}
                    elseif(!(Test-Path -LiteralPath $path -PathType Leaf)){$status='404 Not Found';$body='{"error":"Not found"}'}
                    else{
                        $cursor=$path;$safe=$true
                        while($cursor.Length -ge $rootPath.TrimEnd([IO.Path]::DirectorySeparatorChar).Length){$item=Get-Item -LiteralPath $cursor -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){$safe=$false;break};$next=[IO.Path]::GetDirectoryName($cursor);if(!$next -or $next -eq $cursor){break};$cursor=$next}
                        if(!$safe){$status='403 Forbidden';$body='{"error":"Links forbidden"}'}else{$body=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8);$null=ConvertFrom-Json -InputObject $body}
                    }
                }
            }
            $bytes=[Text.Encoding]::UTF8.GetBytes($body);$headers=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $status`r`nContent-Type: $type`r`nContent-Length: $($bytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nConnection: close`r`n`r`n")
            $stream.Write($headers,0,$headers.Length);$stream.Write($bytes,0,$bytes.Length);$stream.Flush()
        }catch{Write-Output ('请求失败：'+$_.Exception.Message)}finally{$client.Close()}
    }
}finally{$listener.Stop()}
