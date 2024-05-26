using Microsoft.Graph;
using Microsoft.Extensions.Configuration;
using Microsoft.Graph.Models;
using Azure.Identity;
using System;
using System.CommandLine;
using System.CommandLine.Builder;
using System.CommandLine.Parsing;
using System.Net.Http;
using System.Net.Http.Headers;
using graphconsoleapp.Middleware;
using Microsoft.Exchange.WebServices.Data;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Identity.Client;
using SimeonOnboarding.Commands;
using Spectre.Console;
using FolderView = Microsoft.Graph.Models.FolderView;
using Task = System.Threading.Tasks.Task;


namespace SimeonOnboarding
{
    public abstract class Program
    {
        public static async Task Main(string[] args)
        {
            var config = LoadAppSettings();
            if (config == null)
            {
                Console.WriteLine("Invalid appsettings.json file.");
                return;
            }

            var client = GetAuthenticatedGraphClient(config);

            var requestMeUser = await client.Me.GetAsync();
            Console.WriteLine(requestMeUser.Id + ": " + requestMeUser.DisplayName + " <" + requestMeUser.Mail + ">");
            var resultNewUser = await CreateUserAsync(client);
            Console.WriteLine(resultNewUser.Id + ": " + resultNewUser.DisplayName + " <" + resultNewUser.Mail + ">");
            if (resultNewUser == null)
            {
                Console.WriteLine("No user created!");
                Environment.Exit(400);
             }

            var directoryRoles = await client.DirectoryRoles.GetAsync();
            var resultAssignRoles = await AssignRolesToUserAsync(client, resultNewUser);
        }

        public sealed record ExchangeRoles
        {
            public string Id { get; set; }
            public string Description { get; set; }
        }

        private static async Task<ExchangeRoles?> GetExchangeRolesAsync(string accessToken)
        {

            using (HttpClient httpClient = new HttpClient())
            {
                string url = "https://admin.exchange.microsoft.com/beta/RoleGroup";
                httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                HttpResponseMessage response = await httpClient.GetAsync(url);
                string content = await response.Content.ReadAsStringAsync();
                Console.WriteLine(content);
            }

            return null;
        }

        private static async Task<User?> CreateUserAsync(GraphServiceClient client)
        {
            var user = new User
            {
                AccountEnabled = true,
                DisplayName = "Simeon Cloud 3",
                MailNickname = "simeoncloud3",
                UserPrincipalName = "scloud4@exiteblueprint.onmicrosoft.com",
                PasswordProfile = new PasswordProfile
                {
                    ForceChangePasswordNextSignIn = true,
                    Password = "Password1234"
                }
            };
            return await client.Users.PostAsync(user);
        }

        private static async Task<User> AssignRolesToUserAsync(GraphServiceClient client, User user)
        {
            string[] roleIds =
            {
                "3a2c62db-5318-420d-8d74-23affee5d9d5", // Intune Administrator
                "29232cdf-9323-42fd-ade2-1d097af3e4de", // Exchange Administrator
                "fe930be7-5e62-47db-91af-98c3a49a38b1", // User Administrator
                "0526716b-113d-4c15-b2c8-68e3c22b9f80", // Authentication Policy Administrator
                "7698a772-787b-4ac8-901f-60d6b08affd2", // Cloud Device Administrator
                "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", // Application Administrator
                "17315797-102d-40b4-93e0-432062caca18", // Compliance Administrator
                "69091246-20e8-4a56-aa4d-066075b2a7a8", // Teams Administrator
                "fdd7a751-b60b-444a-984c-02652fe8fa1c", // Groups Administrator
                "f28a1f50-f6e7-4571-818b-6a12f2af6b6c", // SharePoint Administrator
                "194ae4cb-b126-40b2-bd5b-6091b380977d" // Security Administrator
            };
            foreach (var roleId in roleIds)
            {
                var request = new Microsoft.Graph.Models.ReferenceCreate
                {
                    OdataId = $"https://graph.microsoft.com/v1.0/directoryObjects/{user.Id}",
                };
                await client.DirectoryRoles[$"roleTemplateId={roleId}"].Members.Ref.PostAsync(request);
            }

            return user;
        }

        private static IConfigurationRoot? LoadAppSettings()
        {
            try
            {
                var config = new ConfigurationBuilder()
                    .SetBasePath(System.IO.Directory.GetCurrentDirectory())
                    .AddJsonFile("appsettings.json", false, true)
                    .Build();

                if (string.IsNullOrEmpty(config["applicationId"]) ||
                    string.IsNullOrEmpty(config["tenantId"]))
                {
                    return null;
                }

                return config;
            }
            catch (System.IO.FileNotFoundException)
            {
                return null;
            }
        }



        private static GraphServiceClient GetAuthenticatedGraphClient(IConfigurationRoot config)
        {
            var scopes = new[]
            {
                "https://graph.microsoft.com//.default"
            };


            var tenantId = "common"; // Multi-tenant apps can use "common",
            var clientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"; // config["applicationId"];

            var options = new InteractiveBrowserCredentialOptions
            {
                TenantId = tenantId,
                ClientId = clientId,
                AuthorityHost = AzureAuthorityHosts.AzurePublicCloud,
                RedirectUri = new Uri("http://localhost"),
            };
            var interactiveCredential =
                new InteractiveBrowserCredential(
                    options); // https://learn.microsoft.com/dotnet/api/azure.identity.interactivebrowsercredential

            var graphClient = new GraphServiceClient(interactiveCredential, scopes);
            return graphClient;
        }
    }
}
//
// namespace exchange
// {
//     class Program
//     {
//         static async System.Threading.Tasks.Task Main(string[] args)
//         {
//             // Using Microsoft.Identity.Client 4.22.0
//
//             // Configure the MSAL client to get tokens
//             var pcaOptions = new PublicClientApplicationOptions
//             {
//                 ClientId = "c5393580-f805-4401-95e8-94b7a6ef2fc2",// ConfigurationManager.AppSettings["appId"],
//                 TenantId = "common",//ConfigurationManager.AppSettings["tenantId"]
//                 RedirectUri = "http://localhost"
//             };
//
//             var pca = PublicClientApplicationBuilder
//                 .CreateWithApplicationOptions(pcaOptions).Build();
//
//             // The permission scope required for EWS access
//             var ewsScopes = new string[] { "https://outlook.office365.com//.default" };
//
//             try
//             {
//                 // Make the interactive token request
//                 var authResult = await pca.AcquireTokenInteractive(ewsScopes).ExecuteAsync();
//
//                 // Configure the ExchangeService with the access token
//                 var ewsClient = new ExchangeService();
//                 ewsClient.Url = new Uri("https://outlook.office365.com/EWS/Exchange.asmx");
//                 ewsClient.Credentials = new OAuthCredentials(authResult.AccessToken);
//
//                 // Make an EWS call
//                 var folders = ewsClient.ManagementRoles;
//
//                     Console.WriteLine($"Folder: {folders}");
//
//             }
//             catch (MsalException ex)
//             {
//                 Console.WriteLine($"Error acquiring access token: {ex}");
//             }
//             catch (Exception ex)
//             {
//                 Console.WriteLine($"Error: {ex}");
//             }
//
//             if (System.Diagnostics.Debugger.IsAttached)
//             {
//                 Console.WriteLine("Hit any key to exit...");
//                 Console.ReadKey();
//             }
//         }
//     }
// }
var rootCommand = new RootCommand
{
    new CreateSimeonUserCommand()
};

var builder = new CommandLineBuilder(rootCommand)
    .UseDefaults()
    .UseHelp()
    .UseDependencyInjection(services =>
    {
        services.AddSingleton(new HttpClient());
        services.AddLogging();
    });

AnsiConsole.MarkupLine($"\nCopyright {DateTime.Now.Year.ToString()} (c)  - [underline blue] CLI[/]");
AnsiConsole.MarkupLine($"Version  [yellow bold]INTERNAL BUILD[/]");
AnsiConsole.MarkupLine($"[grey][/]");
AnsiConsole.MarkupLine($"[grey]This application is intended for use by authorized  employees only." +
                       $"\nUnauthorized access or use of this application is prohibited.[/]");
return builder.Build().Invoke(args);
