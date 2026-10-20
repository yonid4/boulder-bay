"""Query and business logic, one module per API domain.

Functions take an `AsyncSession` and return the client-facing models from `app.api.models`,
so routers stay thin and the logic is testable without HTTP.
"""
