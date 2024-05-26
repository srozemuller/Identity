using System;
using System.Text;
using System.Text.Json;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading.Tasks;
using System.Collections.Generic;
using Microsoft.Identity.Client;
using Microsoft.Graph;
using System.Net;
using System.Security;
using Microsoft.Extensions.Configuration;
using Helpers;

public class MicrosoftLogin
{
    private static string clientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e";
    private static string redirectUri = "http://localhost";

    private static string[] scopes = new string[] { "https://graph.microsoft.com/.default" };
    public static async Task<string> Authenticate()
    {
        var pcaOptions = new PublicClientApplicationOptions
        {
            ClientId = clientId,
            RedirectUri = redirectUri,
        };

        var pca = PublicClientApplicationBuilder.CreateWithApplicationOptions(pcaOptions).Build();
        var accounts = await pca.GetAccountsAsync();

        AuthenticationResult authResult = null;

        try
        {
            authResult = await pca.AcquireTokenInteractive(scopes)
                .WithAccount(accounts.FirstOrDefault())
                .ExecuteAsync();
        }
        catch (MsalException ex)
        {
            Console.WriteLine($"Authentication failed: {ex.Message}");
        }

        return authResult?.AccessToken;
    }
}

public sealed record PasswordProfile
{
    public required string Password { get; init; }
    public bool ForceChangePasswordNextSignIn { get; init; }
}

public sealed record GraphUserRequest
{
    public bool AccountEnabled { get; set; }
    public string DisplayName { get; set; }
    public string MailNickname { get; set; }
    public string UserPrincipalName { get; set; }
    public PasswordProfile PasswordProfile { get; set; }
}

public sealed record GraphUserResponse
{
    public string Id { get; set; }
    public string DisplayName { get; set; }
    public string UserPrincipalName { get; set; }
}

public sealed record GraphUserRoleRequest
{
    public string PrincipalId { get; set; }
    public string RoleDefinitionId { get; set; }
    public string DirectoryScopeId { get; set; }
}

public class User
{
    public static async Task<string?> Create(string accessToken)
    {

        var userPayload = new GraphUserRequest
        {
            AccountEnabled = true,
            DisplayName = "TicTacToe2",
            MailNickname = "tictactoe2",
            UserPrincipalName = "tictactoe2@exiteblueprint.onmicrosoft.com",
            PasswordProfile = new PasswordProfile
            {
                Password = "sU4NOuX3skjNQGx3Uk3n",
                ForceChangePasswordNextSignIn = true
            }
        };
        JsonSerializerOptions defaultJsonSerializerOptions = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = true
        };
        // Serialize the user data to JSON
        var userPayloadJson = JsonSerializer.Serialize(userPayload, defaultJsonSerializerOptions);
        Console.WriteLine(userPayloadJson);

        // Create a StringContent with the JSON data
        var userContent = new StringContent(userPayloadJson, Encoding.UTF8, "application/json");

        using (var httpClient = new HttpClient())
        {
            // Set the authorization header with the access token
            httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            try
            {
                var graphApiEndpoint = "https://graph.microsoft.com/beta/users";
                HttpResponseMessage response = await httpClient.PostAsync(graphApiEndpoint, userContent);

                if (!response.IsSuccessStatusCode)
                {
                    Console.WriteLine($"Error creating user: {response.StatusCode} - {response.ReasonPhrase}, {response.Content.ReadAsStringAsync().Result}");
                    return null;
                }
                string responseBody = await response.Content.ReadAsStringAsync();
                Console.WriteLine("User created successfully:");
                Console.WriteLine(responseBody);
                var userResponse = JsonSerializer.Deserialize<GraphUserResponse>(responseBody, defaultJsonSerializerOptions);
                return userResponse.Id;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error creating user: {ex}");
            }
            return null;
        }
    }
}

public class UserRoleAssisgnment
{
    public static List<GraphUserRoleRequest> CreateCustomObjects(string[] roles, string PrincipalId)
    {
        List<GraphUserRoleRequest> customObjects = new List<GraphUserRoleRequest>();
        foreach (var role in roles)
        {
            var customObject = new GraphUserRoleRequest
            {
                PrincipalId = PrincipalId,
                RoleDefinitionId = role,
                DirectoryScopeId = "/"
            };

            customObjects.Add(customObject);
        }
        return customObjects;
    }
}

class Program
{
    static async Task Main(string[] args)
    {
        var accessToken = await MicrosoftLogin.Authenticate();
        // Create the request content
        await User.Create(accessToken);
    }

}