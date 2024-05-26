using Microsoft.Extensions.Configuration;
using Spectre.Console;

namespace SimeonOnboarding.Commands;

public class CreateSimeonUserCommand : Command<CreateSimeonUserCommandOptions, CreateSimeonUserCommandHandler>
{
    public CreateSimeonUserCommand() : base("CreateSimeonUser", "CreateSimeonUser command")
    {
    }
}

public class CreateSimeonUserCommandOptions : ICommandOptions
{
    
}

public class CreateSimeonUserCommandHandler : ICommandOptionsHandler<CreateSimeonUserCommandOptions>
{
    public async Task<int> HandleAsync(CreateSimeonUserCommandOptions options, CancellationToken cancellationToken)
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

        return 0;
    }
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
