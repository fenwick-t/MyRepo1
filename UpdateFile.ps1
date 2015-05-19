# Assume we have:
# 1. Valid token
# 2. Filename we want to update and content of the updated file
# 3. Username, repo name and branch name
# 4. The file exists in the branch
# This script will update file with content in user's branch

$username = "fenwick-t";
$repo = "MyRepo1";

# headers parametres
$token = "8dcad74b9e059808ecc9113820a5fc0bde741bed";
$headers = @{"Authorization" = "token $token"};

# body parametres
# path to the file (required)
$path = "myTestFile.txt";

# comment to the commit (required)
$message = "update file (source control)";

# content of the file (required, base64 encoded)
#$base64Content = "SGVsbG8gd29ybGQh";
$content = "I need to be encoded";
$bytes = [System.Text.Encoding]::UTF8.GetBytes($content);
$base64Content = [System.Convert]::ToBase64String($bytes);

# branch name (optional) - "master" by default
$branch = "master";

# sha (required)
$jsonMetadata = Invoke-WebRequest -Method Get -Uri "https://api.github.com/repos/$username/$repo/contents/$path";
$metadata = ConvertFrom-Json $jsonMetadata;
$sha = $metadata.sha

$parametres = @{"path" = $path; "message" = $message; "content" = $base64Content; "sha" = $sha; "branch" = $branch};
$jsonBody = ConvertTo-Json $parametres;

Invoke-WebRequest -Method Put -Uri "https://api.github.com/repos/$username/$repo/contents/$path" -Body $jsonBody -Headers $headers