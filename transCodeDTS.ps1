#Поиск mkv файлов со звуковыми дорожками DTS и др. и их перекодировка с помощью ffmpeg
#Исходный файл остается неизменным. Создается новый файл рядом
#Видеодорожки переносятся в новый файл без изменений
#Аудиодорожки - часть переносится без изменний
#Аудиодорожки с некоторыми кодеками перекодируются. Шаблон их поиска - в переменной $streamsToTranscode
#Субтитры - переносятся в новый файл без изменений
#Метаданные всех потоков сохраняются без изменений
#Если есть еще какие-то потоки, они не переносятся
#------------------------------------------------------------------
#Функции
#------------------------------------------------------------------
#Проверяет существование файла
function IsFileExists([string]$pathToTest) {
    return Test-Path  -PathType Leaf -Path $pathToTest
}
#------------------------------------------------------------------
#Начало программы
#------------------------------------------------------------------
Write-Host 'Starting .....'
#Первичные настройки
#regexp выражение для поиска потоков для перекодирования
$streamsToTranscode='Audio: (truehd|dts|flac)'
#Команда для перекодирования аудиопотоков
$transcodeCommand=' ac3 -b:a 448k '
#другие варианты перекодирования аудиопотоков
#$transcodeCommand=' ac3 '
#$transcodeCommand=' aac '
#Команда для копирования потоков без перекодирования
$noTranscodeCommand=' copy '
#не удалять текстовые файлы с логами
$delTxtLogs=$false 
#удалять текстовые файлы с логами
$delTxtLogs=$true

#Начальные значения переменных
$numOfFiles=0 #найдено видеофайлов
$numOfConvertedFiles=0 #сконвертировано видеофайлов
#Текущий путь запуска скрипта. В нем идет поиск ffmpeg.exe и файлов для перекодирования
$cur_path=$PSScriptRoot
#Имя файла в который происходит перекодирование. После перекодирования будет переименован
$oFileName='_outfile.mkv' 
#Имя файла для вывода информации о потоках
$infoFileName='_outfile.txt'
#Имя файла для вывода работы ffmpeg
$ffmpegfilename='_outfile_ffmpeg.txt'
#удалим предыдущий файл вывода, если он есть, чтобы он не попал в выборку
if (IsFileExists($oFileName)) {Remove-Item $oFileName}
#Проверяем, что есть ffmpeg
if (-not((IsFileExists($cur_path+'\ffmpeg.exe')))) {
    #Окончание программы
    Write-Host -ForegroundColor Red 'ERROR! ffmpeg.exe not found in current folder'
    Exit
}
#------------------------------------------------------------------
#Основной текст программы
#------------------------------------------------------------------
#Просматриваем текущую папку и берем по очереди все файлы .mkv
#обход файлов
$FileList= Get-ChildItem -Path $cur_path -Force -ErrorAction SilentlyContinue -File -Name -Include @("*.mp4", "*.mkv")
foreach ($FileSpec in $FileList) {
    #перебор файлов
    #$FileSpec - имя очередного файла из выборки
    $numVideoStreams=0  #нумеруем первый video поток с нуля!
    $numSubStreams=0  #нумеруем первый поток субтитров с нуля!
    $numAudioStreams=0  #нумеруем первый аудио поток с нуля!
    $numToTranscode=0 #количество аудио потоков для перекодирования
    #Проверяем существование файла
    if (-not (IsFileExists($FileSpec))) { # почему-то его не оказалось на месте
        Continue 
    }
    $numOfFiles=$numOfFiles+1
    write-host 'Found file : ' -NoNewline
    write-host -ForegroundColor Green $FileSpec
    #это строка, которая будет подана на вход ffmpeg. начинеаем ее собирать
    $transcodeString = '-i "'+$FileSpec+'" -map 0 '
    #Вывод в файл информации о потоках
    & cmd /c ffmpeg.exe -i $FileSpec *> $infoFileName
    foreach($fline in Get-Content $infoFileName) {
        #разбор строк
        #$fline - это очредная строка из файла
        #нужно скопировать без изменений все видеопотоки (не тестировалось на многих видеопотоках) и все потоки с субтитрами
        if ($fline -match 'Stream #0:') {
            if ($fline -match ': Video: ') { #это видеодорожка, копируем ее
                $numVideoStreams=$numVideoStreams+1 #счетчик
                $transcodeString=$transcodeString+'-c:v:'+($numVideoStreams-1)+$noTranscodeCommand
            } 
            elseif ($fline -match ': Audio: ') { #это аудиодорожка, проверяем ее
                $numAudioStreams=$numAudioStreams+1 #счетчик
                #------------------------------------------------------------------
                #здесь основная логика
                #------------------------------------------------------------------
                if ($fline -match $streamsToTranscode) {
                    $numToTranscode=$numToTranscode+1 #счетчик
                    #эту дорожку перекодировать
                    $transcodeString=$transcodeString+'-c:a:'+($numAudioStreams-1)+$transcodeCommand

                } else {
                    $transcodeString=$transcodeString+'-c:a:'+($numAudioStreams-1)+$noTranscodeCommand
                }
                #------------------------------------------------------------------
            }
            elseif ($fline -match ': Subtitle: ') { #это субтитры, копируем их
                $numSubStreams=$numSubStreams+1 #счетчик
                $transcodeString=$transcodeString+'-c:s:'+($numSubStreams-1)+$noTranscodeCommand
            } 
        }
        #write-host $fline
    }
    $transcodeString=$transcodeString+' -y '+$oFileName
    write-host $numAudioStreams" total audio streams"
    if ($numToTranscode -gt 0) { #есть дорожки для конвертации. обработка файла
        write-host $numToTranscode" streams to transcode"
        Write-Host 'transcoding ....'
        #ниже - строка для проверки вывода. для проверки ее нужно раскомментировать
        #write-host 'ffmpeg.exe' $transcodeString
        #------------------------------------------------------------------
        #здесь вся работа происходит
        #------------------------------------------------------------------
        Start-Process -FilePath  .\ffmpeg.exe -ArgumentList $transcodeString -Wait -NoNewWindow -RedirectStandardError $ffmpegfilename
        #------------------------------------------------------------------
        if (IsFileExists($oFileName)) { #выходной файл есть. считаем, что перекодирование завершено
            $numOfConvertedFiles=$numOfConvertedFiles+1
            #переименовать выходной видеофайл
            $new_video_file=$FileSpec+'.new.mkv'
            if (IsFileExists($new_video_file)) {Remove-Item $new_video_file}
            if (IsFileExists($oFileName)) {Rename-Item -LiteralPath $oFileName -NewName $new_video_file -Force}
        } else { #что-то пошло не так. нет выходного файла
            Write-Host -ForegroundColor Red 'Error during transcoding. See diagnostics in .txt files'
            if ($delTxtLogs) {Write-Host -ForegroundColor Red 'Error during transcoding. Something wrong. To see diagnostic .txt files you need to comment string $delTxtLogs=$true'} 
            else {Write-Host -ForegroundColor Red 'Error during transcoding. See diagnostics in .txt files'}
        }
        if ($delTxtLogs) { #удалить текстовые файлы
            if (IsFileExists($infoFileName)) {Remove-Item $infoFileName}
            if (IsFileExists($ffmpegfilename)) {Remove-Item $ffmpegfilename}
        } else { #оставить текстовые файлы
            #переименовать файл вывода с потоками
            $ffprobe_out=$FileSpec+'.txt'
            if (IsFileExists($ffprobe_out)) {Remove-Item $ffprobe_out}
            if (IsFileExists($infoFileName)) {Rename-Item -LiteralPath $infoFileName -NewName $ffprobe_out -Force}
            #переименовать файл вывода ffmpeg
            $ffmpeg_out=$FileSpec+'.ffmpeg.txt'
            if (IsFileExists($ffmpeg_out)) {Remove-Item $ffmpeg_out}
            if (IsFileExists($ffmpegfilename)) {Rename-Item -LiteralPath $ffmpegfilename -NewName $ffmpeg_out -Force}
        }
    } else {
        #в этом файле нет дорожек для перекодирования
        Write-Host 'Nothing to transcode'
        #удаляем следы
        if (IsFileExists($infoFileName)) {Remove-Item $infoFileName}
    } #конец обработки файла
} #конец перебора файлов
write-host $numOfFiles 'video files found in folder'
write-host $numOfConvertedFiles 'video files transcoded'
#
