namespace Mango.Shared.Abstractions;

/// <summary>
/// Marker interface for CQRS Queries. Queries are read-only and never mutate state.
/// </summary>
/// <typeparam name="TResult">The type returned by the query handler.</typeparam>
public interface IQuery<out TResult> : MediatR.IRequest<TResult> { }
