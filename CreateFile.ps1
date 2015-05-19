# Assume we have:
# 1. Valid token
# 2. Filename we want to create and content of the new file
# 3. Username, repo name and branch name
# This script will create a new file with given content into user's branch

$username = "fenwick-t";
$repo = "MyRepo1";

# headers parametres
$token = "8dcad74b9e059808ecc9113820a5fc0bde741bed";
$headers = @{"Authorization" = "token $token"};

# body parametres
# path to the file (required)
$path = "myTestFile.txt";

# comment to the commit (required)
$message = "create file (source control)";

# content of the file (required, base64 encoded)
#$base64Content = "bXkgbmV3IGZpbGUgY29udGVudHM=";
$content = "Hello world!";
$bytes = [System.Text.Encoding]::UTF8.GetBytes($content);
$base64Content = [System.Convert]::ToBase64String($bytes);

# branch name (optional) - "master" by default
$branch = "master";

$parametres = @{"path" = $path; "message" = $message; "content" = $base64Content; "branch" = $branch};
$jsonBody = ConvertTo-Json $parametres;

invoke-WebRequest -Method Put -Uri "https://api.github.com/repos/$username/$repo/contents/$path" -Body $jsonBody -Headers $headers
