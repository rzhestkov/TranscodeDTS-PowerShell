#Поиск mkv файлов со звуковыми дорожками DTS и др. и их перекодировка с помощью ffmpeg
#Создается новый файл рядом
#Видеодорожки - переносятся в новый файл без изменений
#Аудиодорожки - большая часть переносится без изменний
#Аудиодорожки с некоторыми кодеками перекодируются. Шаблон их поиска - в переменной $streamsToRecode
#Субтитры - переносятся в новый файл без изменений
#Метаданные всех потоков сохраняюся без изменений

#------------------------------------------------------------------
#Функции
#------------------------------------------------------------------
#Проверяет существование файла
function IsFileExists([string]$pathToTest) {
    #проверит наличие пути https://fixmypc.ru/post/test-path-v-powershell-proverka-sushchestvovaniia-faila-i-papki/
    $result=$true
        if (-not(Test-Path -Path $pathToTest)) { # нет такого пути
            #write-host Path: $pathToTest not found
            $result=$false
        } elseif (-not(Test-Path -PathType Leaf -Path $pathToTest)) { # это не файл
            $result=$false
        }
        return $result
    }
#------------------------------------------------------------------
#Начало работы программы
#------------------------------------------------------------------
Write-Host 'Starting .....'
#Первичные настройки
#regexp выражение для поиска потоков для перекодирования
$streamsToRecode='Audio: (truehd|dts|flac)'
#Команда для перекодирования аудиопотоков
$recodeCommand=' ac3 -b:a 448k '
#другие варианты перекодирования аудиопотоков
#$recodeCommand=' ac3 '
#$recodeCommand=' aac '
#Команда для копирования потоков без перекодирования
$norecodeCommand=' copy '
#не удалять текстовые файлы с логами
$delTxtLogs=$false 
#удалять текстовые файлы с логами
#$delTxtLogs=$true

#Начальные значения переменных
$numOfFiles=0 #найдено видеофайлов
$numOfConvertedFiles=0 #сконвертировано видеофайлов
#Текущий путь запуска скрипта. В нем идет поиск ffprobe и ffmpeg и файлов для перекодирования
$cur_path=$PSScriptRoot
#Имя файла в который происходит перекодирование. После перекодирования будет переименован
$ofilename='_outfile.mkv' 
#Имя файла для вывода ffprobe и анализа потоков
$infofilename='_outfile.txt'
#Имя файла для вывода работы ffmpeg
$ffmpegfilename='_outfile_ffmpeg.txt'
#удалим предыдущий файл вывода, если он есть, чтобы он не попал в выборку
if (IsFileExists($ofilename)) {Remove-Item $ofilename}
#Проверяем, что есть ffmpeg
#if (-not((IsFileExists($cur_path+'\ffmpeg.exe')) -and (IsFileExists($cur_path+'\ffprobe.exe')))) {
if (-not((IsFileExists($cur_path+'\ffmpeg.exe')))) {
    #Окончание программы
    Write-Host -ForegroundColor Red 'ERROR!'
    Write-Host -ForegroundColor Red 'ffmpeg.exe not found in current folder'
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
    #$FileSpec - это имя очредного файла
    $numVideoStreams=0  #нумеруем первый video поток с нуля!
    $numSubStreams=0  #нумеруем первый поток субтитров с нуля!
    $numAudioStreams=0  #нумеруем первый аудио поток с нуля!
    $numToRecode=0 #количество аудио потоков для перекодирования
    #Проверяем существование файла
    if (-not (IsFileExists($FileSpec))) { # почему-то его не оказалось на месте
        Continue 
    }
    $numOfFiles=$numOfFiles+1
    write-host 'Found file : ' -NoNewline
    write-host -ForegroundColor Green $FileSpec
    #это строка, которая будет подана на вход ffmpeg. начинеаем ее собирать
    $recodeString = '-i "'+$FileSpec+'" -map 0 '
    #Вывод в файл информации о потоках
    & cmd /c ffmpeg.exe -i $FileSpec *> $infofilename
    foreach($fline in Get-Content $infofilename) {
        #разбор строк
        #$fline - это очредная строка из файла
        #нужно скопировать без изменений все видеопотоки (не тестировалось на многих видеопотоках) и все потоки с субтитрами
        if ($fline -match 'Stream #0:') {
            if ($fline -match ': Video: ') { #это видеодорожка, копируем ее
                $numVideoStreams=$numVideoStreams+1 #счетчик
                $recodeString=$recodeString+'-c:v:'+($numVideoStreams-1)+$norecodeCommand
            } 
            elseif ($fline -match ': Audio: ') { #это аудиодорожка, проверяем ее
                $numAudioStreams=$numAudioStreams+1 #счетчик
                #------------------------------------------------------------------
                #здесь основная логика
                #------------------------------------------------------------------
                if ($fline -match $streamsToRecode) {
                    $numToRecode=$numToRecode+1 #счетчик
                    #эту дорожку перекодировать
                    $recodeString=$recodeString+'-c:a:'+($numAudioStreams-1)+$recodeCommand

                } else {
                    $recodeString=$recodeString+'-c:a:'+($numAudioStreams-1)+$norecodeCommand
                }
                #------------------------------------------------------------------
            }
            elseif ($fline -match ': Subtitle: ') { #это субтитры, копируем их
                $numSubStreams=$numSubStreams+1 #счетчик
                $recodeString=$recodeString+'-c:s:'+($numSubStreams-1)+$norecodeCommand
            } 
        }
        #write-host $fline
    }
    $recodeString=$recodeString+' -y '+$ofilename
    write-host $numAudioStreams" total audio streams"
    if ($numToRecode -gt 0) { #есть дорожки для конвертации. обработка файла
        write-host $numToRecode" streams to recode"
        Write-Host 'Recoding ....'
        #ниже - строка для проверки вывода. для проверки ее нужно раскомментировать
        #write-host 'ffmpeg.exe' $recodeString
        #------------------------------------------------------------------
        #здесь вся работа происходит
        #------------------------------------------------------------------
        Start-Process -FilePath  .\ffmpeg.exe -ArgumentList $recodeString -Wait -NoNewWindow -RedirectStandardError $ffmpegfilename
        #------------------------------------------------------------------
        if (IsFileExists($ofilename)) { #выходной файл есть. считаем, что перекодирование завершено
            $numOfConvertedFiles=$numOfConvertedFiles+1
            #переименовать выходной видеофайл
            $new_video_file=$FileSpec+'.new.mkv'
            if (IsFileExists($new_video_file)) {Remove-Item $new_video_file}
            if (IsFileExists($ofilename)) {Rename-Item -LiteralPath $ofilename -NewName $new_video_file -Force}
        } else { #что-то пошло не так. нет выходного файла
            Write-Host -ForegroundColor Red 'Error during recoding. See diagnostics in .txt files'
            if ($delTxtLogs) {Write-Host -ForegroundColor Red 'Error during recoding. Somthing wrong. To see diagnostic files you need to comment string $delTxtLogs=$true'} 
            else {Write-Host -ForegroundColor Red 'Error during recoding. See diagnostics in .txt files'}
        }
        if ($delTxtLogs) { #удалить текстовые файлы
            if (IsFileExists($infofilename)) {Remove-Item $infofilename}
            if (IsFileExists($ffmpegfilename)) {Remove-Item $ffmpegfilename}
        } else { #оставить текстовые файлы
            #переименовать файл вывода ffprobe
            $ffprobe_out=$FileSpec+'.txt'
            if (IsFileExists($ffprobe_out)) {Remove-Item $ffprobe_out}
            if (IsFileExists($infofilename)) {Rename-Item -LiteralPath $infofilename -NewName $ffprobe_out -Force}
            #переименовать файл вывода ffmpeg
            $ffmpeg_out=$FileSpec+'.ffmpeg.txt'
            if (IsFileExists($ffmpeg_out)) {Remove-Item $ffmpeg_out}
            if (IsFileExists($ffmpegfilename)) {Rename-Item -LiteralPath $ffmpegfilename -NewName $ffmpeg_out -Force}
        }
    } else {
        #в этом файле нет дорожек для перекодирования
        Write-Host 'Nothing to recode'
        #удаляем следы
        if (IsFileExists($infofilename)) {Remove-Item $infofilename}
    } #конец обработки файла
} #конец перебора файлов
write-host $numOfFiles 'video files found in folder'
write-host $numOfConvertedFiles 'video recoded'
#
