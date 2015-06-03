using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using Octokit;

namespace OctokitTest
{
    class GitHubConnect
    {
        public static void Main()
        {
            var github = new GitHubClient(new ProductHeaderValue("HelloWorld"));
            github.Credentials = new Credentials("34ff14708b1a2b2cc3158703f9edd3e4d35756b1");
            var res = github.GitDatabase.Tree.GetRecursive("fenwick-t", "MyRepo1", "de4d316bfe286862c52206cb99042563dcd7fd09").Result;
            var items = res.Tree.ToList();
            for (int i = items.Count - 1; i >= 0; i--)
            {
                if (items[i].Type == TreeType.Blob)
                { 
                    var blob = github.GitDatabase.Blob.Get("fenwick-t", "MyRepo1", items[i].Sha).Result;           
                    var content = Convert.FromBase64String(blob.Content);
                    Console.WriteLine(Encoding.Default.GetString(content));
                }
            }
            Console.Read();

        }
        
    }
}
