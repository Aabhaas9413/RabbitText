namespace Mango.Shared.Abstractions;

/// <summary>
/// Marker interface for CQRS Commands that return a result.
/// Commands mutate state and are handled by a single handler.
/// </summary>
/// <typeparam name="TResult">The type returned by the command handler.</typeparam>
public interface ICommand<out TResult> : MediatR.IRequest<TResult> { }

/// <summary>
/// Marker interface for fire-and-forget CQRS Commands (no return value).
/// </summary>
public interface ICommand : MediatR.IRequest { }
