@echo off
setlocal EnableExtensions
pushd "%~dp0" >nul
if errorlevel 1 goto :fail

set "REPO_NAME=finance-dashboard"
set "REPO_URL=https://github.com/vioze321/finance-dashboard.git"
set "CREATE_REPO_URL=https://github.com/new?name=finance-dashboard&visibility=public"

where git >nul 2>nul
if errorlevel 1 (
    echo ERROR: Git is not installed or is not available in PATH.
    echo Install Git for Windows, then reopen this file.
    goto :fail
)

git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
    echo Initializing the dashboard repository on branch main...
    git init -b main
    if errorlevel 1 goto :fail
)

for /f "delims=" %%B in ('git branch --show-current') do set "CURRENT_BRANCH=%%B"
if /i not "%CURRENT_BRANCH%"=="main" (
    echo ERROR: Expected branch main, but the current branch is "%CURRENT_BRANCH%".
    goto :fail
)

git rev-parse -q --verify REBASE_HEAD >nul 2>nul
if not errorlevel 1 (
    echo ERROR: A Git rebase is already in progress. Resolve it before deploying.
    goto :fail
)

for /f "delims=" %%R in ('git remote get-url origin 2^>nul') do set "ORIGIN_URL=%%R"
if not defined ORIGIN_URL (
    echo Connecting origin to %REPO_URL%
    git remote add origin "%REPO_URL%"
    if errorlevel 1 goto :fail
) else if /i not "%ORIGIN_URL%"=="%REPO_URL%" (
    echo ERROR: origin points to "%ORIGIN_URL%" instead of "%REPO_URL%".
    echo Edit REPO_URL in deploy.cmd if you want to use another repository.
    goto :fail
)

echo.
echo Staging only the dashboard page, deploy script, and Pages workflow...
git add -- index.html deploy.cmd .github/workflows/pages.yml
if errorlevel 1 goto :fail

git diff --cached --quiet
if errorlevel 2 goto :fail
if errorlevel 1 (
    git commit -m "Deploy finance dashboard"
    if errorlevel 1 (
        echo ERROR: Commit failed. Check your Git name and email configuration.
        goto :fail
    )
)

git ls-remote origin >nul 2>nul
if errorlevel 1 (
    echo.
    echo The GitHub repository does not exist yet or is not reachable.
    echo Create an EMPTY public repository named %REPO_NAME% in the opened page.
    echo Do not add a README, license, or .gitignore during creation.
    start "" "%CREATE_REPO_URL%"
    pause
    git ls-remote origin >nul 2>nul
    if errorlevel 1 (
        echo ERROR: Repository is still unavailable. Create it, then run deploy.cmd again.
        goto :fail
    )
)

git ls-remote --exit-code origin refs/heads/main >nul 2>nul
if errorlevel 1 (
    git push -u origin main
    if errorlevel 1 goto :fail
) else (
    git fetch origin main
    if errorlevel 1 goto :fail
    git pull --rebase origin main
    if errorlevel 1 (
        echo ERROR: Rebase failed. Resolve the Git conflict, then run deploy.cmd again.
        goto :fail
    )
    git push -u origin main
    if errorlevel 1 goto :fail
)

echo.
echo Deploy push completed. GitHub Actions will publish the Pages site.
echo Repository: https://github.com/vioze321/%REPO_NAME%
echo Workflow:   https://github.com/vioze321/%REPO_NAME%/actions
echo Pages URL:  https://vioze321.github.io/%REPO_NAME%/
popd
pause
exit /b 0

:fail
echo.
echo Deployment stopped. Review the error above; no force push was attempted.
popd
pause
exit /b 1