# Mox mock of the Tesla adapter. Configured as the Tesla adapter in the test env
# (see config/test.exs), so every Tesla client built without an explicit adapter
# routes its HTTP calls through here, where tests drive responses with Mox
# `expect`/`stub` (and `Tesla.Test` helpers).
Mox.defmock(ExShopifyApp.MockTeslaAdapter, for: Tesla.Adapter)
