defmodule Jido.Chat.Telegram.IngressSubscriptionTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Telegram.Adapter

  defmodule SubscriptionTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(token, "setWebhook", payload, opts) do
      send(self(), {:set_webhook, token, payload, opts})
      {:ok, true}
    end

    def call(token, "getWebhookInfo", payload, opts) do
      send(self(), {:get_webhook_info, token, payload, opts})

      {:ok,
       %{
         "url" => "https://example.test/webhooks/telegram",
         "pending_update_count" => 2,
         "allowed_updates" => ["message", "callback_query"]
       }}
    end

    def call(token, "deleteWebhook", payload, opts) do
      send(self(), {:delete_webhook, token, payload, opts})
      {:ok, true}
    end
  end

  test "ensure_ingress_subscription/2 sets the Telegram webhook" do
    assert {:ok, subscription} =
             Adapter.ensure_ingress_subscription("bridge_tg",
               token: "bot-token",
               transport: SubscriptionTransport,
               ingress: %{
                 mode: :webhook,
                 target_url: "https://example.test/webhooks/telegram",
                 allowed_updates: ["message", "callback_query"],
                 secret_token: "secret-token",
                 drop_pending_updates: true,
                 raw: %{max_connections: 20}
               }
             )

    assert subscription.subscription_id == "telegram:webhook:bridge_tg"
    assert subscription.target_url == "https://example.test/webhooks/telegram"
    assert subscription.status == :active
    assert subscription.metadata == %{provider: :telegram, mode: :webhook}
    assert subscription.raw == true

    assert_received {:set_webhook, "bot-token", payload, opts}
    assert payload["url"] == "https://example.test/webhooks/telegram"
    assert payload["allowed_updates"] == ["message", "callback_query"]
    assert payload["secret_token"] == "secret-token"
    assert payload["drop_pending_updates"] == true
    assert payload["max_connections"] == 20
    assert opts == []
  end

  test "list_ingress_subscriptions/2 returns the active Telegram webhook" do
    assert {:ok, [subscription]} =
             Adapter.list_ingress_subscriptions("bridge_tg",
               token: "bot-token",
               transport: SubscriptionTransport
             )

    assert subscription.subscription_id == "telegram:webhook:bridge_tg"
    assert subscription.target_url == "https://example.test/webhooks/telegram"
    assert subscription.status == :active

    assert subscription.metadata == %{
             provider: :telegram,
             mode: :webhook,
             pending_update_count: 2,
             allowed_updates: ["message", "callback_query"]
           }

    assert_received {:get_webhook_info, "bot-token", %{}, []}
  end

  test "delete_ingress_subscription/3 deletes the Telegram webhook" do
    assert {:ok, subscription} =
             Adapter.delete_ingress_subscription(
               "bridge_tg",
               "telegram:webhook:bridge_tg",
               token: "bot-token",
               transport: SubscriptionTransport,
               drop_pending_updates: true
             )

    assert subscription.subscription_id == "telegram:webhook:bridge_tg"
    assert subscription.status == :deleted
    assert subscription.raw == true

    assert_received {:delete_webhook, "bot-token", %{"drop_pending_updates" => true}, []}
  end

  test "ingress subscription callbacks are unsupported for polling mode" do
    opts = [token: "bot-token", transport: SubscriptionTransport, ingress: %{mode: :polling}]

    assert {:error, :unsupported} = Adapter.ensure_ingress_subscription("bridge_tg", opts)
    assert {:error, :unsupported} = Adapter.list_ingress_subscriptions("bridge_tg", opts)

    assert {:error, :unsupported} =
             Adapter.delete_ingress_subscription("bridge_tg", "telegram:webhook:bridge_tg", opts)
  end
end
