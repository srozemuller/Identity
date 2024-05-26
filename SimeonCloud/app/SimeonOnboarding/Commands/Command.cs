using System.CommandLine;
using System.CommandLine.NamingConventionBinder;
using Microsoft.Extensions.DependencyInjection;

namespace SimeonOnboarding.Commands;

public interface ICommandOptions
{
}

public interface ICommandOptionsHandler<in TOptions>
{
    Task<int> HandleAsync(TOptions options, CancellationToken cancellationToken);
}

public abstract class Command<TOptions, TOptionsHandler> : Command
    where TOptions : class, ICommandOptions
    where TOptionsHandler : class, ICommandOptionsHandler<TOptions>
{
    protected Command(string name, string description)
        : base(name, description)
    {
        Handler = CommandHandler.Create<TOptions, IServiceProvider, CancellationToken>(HandleOptions);
    }

    private static async Task<int> HandleOptions(TOptions options, IServiceProvider serviceProvider, CancellationToken cancellationToken)
    {
        // True dependency injection happening here
        var handler = ActivatorUtilities.CreateInstance<TOptionsHandler>(serviceProvider);
        return await handler.HandleAsync(options, cancellationToken);
    }
}
