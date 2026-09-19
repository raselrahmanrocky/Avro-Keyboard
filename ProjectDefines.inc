{$Define BetaVersion}
{.$Define PortableOn}
{
  DebugLog is OFF: no component writes a log file any more. DebugLog.Log()
  emits to the debugger only (OutputDebugString) and even that is compiled
  out until this define is turned back on - uncomment the line below and
  attach DebugView to see the diagnostics live. Nothing is written to disk
  either way.
}
{.$Define DebugLog}
