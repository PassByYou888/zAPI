# 检查 PATH 中是否存在 lazbuild.exe
if (-not (Get-Command "lazbuild.exe" -ErrorAction SilentlyContinue)) {
    Write-Host "在系统环境参数里面,设置一个Lazarus的路径就可以编译了。" -ForegroundColor Red
    Write-Host "错误：未找到 lazbuild.exe，请确保 Lazarus 已安装，并将 lazbuild.exe 所在目录添加到 PATH 环境变量中。" -ForegroundColor Red
    Read-Host "按 Enter 键退出"
    exit 1
}

# 编译各个项目
$projects = @(
    "fpc_tester_for_zAPI.lpi",
    "zAPIBenchClient.lpi",
    "zAPIBenchServer.lpi",
    "zAPIBench_API_Check.lpi",
    ".\pascal4py\call_py.lpi",
    "..\Py\bridge\pascal\pascal_cross_test.lpi"
)

foreach ($proj in $projects) {
    Write-Host "正在编译 $proj ..."
    & lazbuild.exe -B $proj
    if ($LASTEXITCODE -ne 0) {
        Write-Host "编译 $proj 失败，错误代码 $LASTEXITCODE" -ForegroundColor Red
        Read-Host "按 Enter 键退出"
        exit $LASTEXITCODE
    }
}

Write-Host "所有项目编译完成。" -ForegroundColor Green
