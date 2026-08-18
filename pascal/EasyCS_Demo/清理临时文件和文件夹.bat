@echo off
rmdir /q /s CrossSocket\__history
rmdir /q /s CrossSocket\__recovery
rmdir /q /s GYunits\__history
rmdir /q /s GYunits\__recovery
rmdir /q /s GYIntraweb\__history
rmdir /q /s GYIntraweb\__recovery
rmdir /q /s GYunitsReports\__history
rmdir /q /s GYunitsReports\__recovery
rmdir /q /s temp
rmdir /q /s __history
rmdir /q /s __recovery
rmdir /q /s Android
rmdir /q /s Android64
rmdir /q /s iOSDevice64
rmdir /q /s iOSSimulator
rmdir /q /s Linux64
rmdir /q /s OSX64
rmdir /q /s Win32
rmdir /q /s Win64
rmdir /q /s TempFMX
rmdir /q /s TempVCL
rmdir /q /s GYRestServer.log
rmdir /q /s GYRestServerV.log
rmdir /q /s GYRestclient.log
rmdir /q /s Token
rmdir /q /s Bin\GYRestServer.log
rmdir /q /s Bin\GYRestServerV.log
rmdir /q /s Bin\GYRestclient.log
rmdir /q /s Bin\Token
rmdir /q /s Bin\GYRestServerCheck.log
rmdir /q /s Bin\temp
del /s *.~*
del /s *.dcu
del /s *.dsk
del /s *.hpp
del /s *.ddp
del /s *.mps
del /s *.mpt
del /s *.bak
del /s *.dof
del /s *.cfg
del /s *.log
del /s *.dproj.local
del /s *.identcache
del /s *.deployproj
del /s *.dproj.local
del /s *.groupproj.local
del /s GYRestServer.res
del /s GYRestServer.skincfg
del /s GYRestServerV.res
del /s GYRestServerV.skincfg
del /s GYRestclient.res
del /s GYRestclient.skincfg
del /s *.tmp
exit
