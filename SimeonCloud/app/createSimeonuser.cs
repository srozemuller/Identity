using System;
using Microsoft.Identity.Client;

public class MicrosoftLogin
{
    private static string clientId = "1950a258-227b-4e31-a9cf-717495945fc2"";
    private static string redirectUri = "http://localhost";

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

class Program
{
    static async Task Main(string[] args)
    {
        var accessToken = await MicrosoftLogin.Authenticate();

        if (!string.IsNullOrEmpty(accessToken))
        {
            Console.WriteLine("Logged in successfully!");
            Console.WriteLine($"Access Token: {accessToken}");
        }
        else
        {
            Console.WriteLine("Login failed.");
        }
    }
}