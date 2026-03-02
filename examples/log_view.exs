defmodule LogViewDemo do
  use Breeze.View

  @max_entries 400

  def mount(_opts, term) do
    :timer.send_interval(250, :tick)

    logs = seed_logs()

    log_view = %{
      follow: true,
      selected_id: List.last(logs) && List.last(logs).id,
      visible: length(logs),
      total: length(logs),
      offset: 0
    }

    term =
      term
      |> focus("logs")
      |> assign(logs: logs, seq: length(logs), max_entries: @max_entries, log_view: log_view)

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box>
      <box style="border width-screen height-20">
        <box
          id="logs"
          focusable
          implicit={Breeze.LogView}
          br-change="log-change"
          log-max-entries={"#{@max_entries}"}
          style="width-screen height-18 overflow-scroll"
        >
          <box
            :for={entry <- @logs}
            value={entry.id}
            log-id={entry.id}
            level={entry.level}
            message={entry.message}
            style="width-screen"
          >
            <%= Breeze.LogView.format_entry(entry) %>
          </box>
        </box>
        <box style="absolute left-1 top-20 width-screen height-1 overflow-hidden bg-238 text-15 bold">
          <%= LogViewDemo.status_line(@log_view, length(@logs)) %>
        </box>
      </box>
    </box>
    """
  end

  def handle_info(:tick, term) do
    seq = term.assigns.seq + 1

    {level, source, message, metadata} =
      case rem(seq, 14) do
        0 ->
          {:error, :my_app,
           "Unhandled exception in ReportWorker: ** (DBConnection.ConnectionError) tcp recv: closed",
           %{job: "ReportWorker", retry_in: "5s"}}

        1 ->
          {:warning, :oban, "queue=default lag=2.3s jobs_waiting=42", %{queue: "default"}}

        2 ->
          {:debug, :telemetry, "phoenix.endpoint.stop duration=18234µs route=/api/projects",
           %{event: "phoenix.endpoint.stop"}}

        3 ->
          {:info, :phoenix, "GET /api/projects 200 in 18ms", %{method: "GET", status: 200}}

        4 ->
          {:info, :ecto,
           "QUERY OK source=\"projects\" db=3.4ms decode=0.8ms queue=0.2ms idle=7.1ms",
           %{source: "projects"}}

        5 ->
          {:debug, :my_app, "cache hit key=user:#{Enum.random(1000..9999)}", %{cache: "session"}}

        6 ->
          {:info, :phoenix, "POST /api/reports 202 in 27ms", %{method: "POST", status: 202}}

        7 ->
          {:warning, :ecto, "QUERY SLOW source=\"events\" db=145.6ms", %{source: "events"}}

        8 ->
          {:debug, :telemetry,
           "vm.memory total=#{Enum.random(90..130)}MB process=#{Enum.random(40..70)}MB",
           %{event: "vm.memory"}}

        9 ->
          {:info, :my_app, "job SyncAccounts finished in #{Enum.random(120..450)}ms",
           %{job: "SyncAccounts"}}

        10 ->
          {:error, :phoenix,
           "** (RuntimeError) expected assigns.current_user to be set in MyAppWeb.DashboardLive",
           %{module: "MyAppWeb.DashboardLive"}}

        11 ->
          {:info, :oban, "job=EmailDigestWorker completed attempt=1", %{queue: "mailers"}}

        12 ->
          {:warning, :my_app, "rate limiter tripped bucket=api:write", %{bucket: "api:write"}}

        _ ->
          {:info, :phoenix, "GET /healthz 200 in 2ms", %{method: "GET", status: 200}}
      end

    entry = %{
      id: seq,
      timestamp: DateTime.utc_now(),
      level: level,
      source: source,
      message: message,
      metadata: Map.merge(metadata, %{pid: inspect(self()), seq: seq})
    }

    logs = Breeze.LogView.push(term.assigns.logs, entry, term.assigns.max_entries)
    {:noreply, assign(term, logs: logs, seq: seq)}
  end

  def handle_info(_, term), do: {:noreply, term}

  def handle_event("log-change", payload, term) do
    {:noreply, assign(term, log_view: Map.merge(term.assigns.log_view, payload))}
  end

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}

  def status_line(log_view, total_logs, viewport_height \\ 18) do
    follow = Map.get(log_view, :follow, true)
    total = max(total_logs, 0)
    max_offset = max(total - viewport_height, 0)

    offset =
      if follow do
        max_offset
      else
        log_view
        |> Map.get(:offset, 0)
        |> max(0)
        |> min(max_offset)
      end

    "f=#{follow} · ↑↓/jk pgup/pgdn home/end · offset=#{offset} total=#{total} · q"
  end

  defp seed_logs do
    now = DateTime.utc_now()

    events = [
      {:info, :phoenix, "GET / 200 in 7ms", %{request_id: "F6x9d2"}},
      {:debug, :telemetry, "phoenix.endpoint.start route=/", %{event: "phoenix.endpoint.start"}},
      {:info, :ecto, "QUERY OK source=\"users\" db=1.2ms idle=4.0ms", %{source: "users"}},
      {:warning, :my_app, "retrying upstream request service=billing", %{attempt: 2}},
      {:info, :oban, "job=CleanupSessionsWorker completed in 43ms", %{queue: "maintenance"}},
      {:error, :my_app, "** (MatchError) no match of right hand side value: {:error, :timeout}",
       %{module: "MyApp.Billing"}},
      {:info, :phoenix, "GET /api/users/42 200 in 13ms", %{request_id: "F6x9d8"}},
      {:debug, :telemetry, "vm.run_queue cpu=2 io=0", %{event: "vm.run_queue"}},
      {:warning, :ecto, "QUERY SLOW source=\"invoices\" db=96.4ms", %{source: "invoices"}},
      {:info, :my_app, "websocket connected topic=alerts:user:42", %{transport: "websocket"}}
    ]

    events
    |> Enum.with_index(1)
    |> Enum.map(fn {{level, source, message, metadata}, idx} ->
      %{
        id: idx,
        timestamp: DateTime.add(now, idx - length(events), :second),
        level: level,
        source: source,
        message: message,
        metadata: metadata
      }
    end)
  end
end

Breeze.Server.start_link(view: LogViewDemo)
:timer.sleep(100_000)
