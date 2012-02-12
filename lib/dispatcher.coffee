Doctor = require './doctor'
ControlChannel = require './control_channel'
AuditLog = require './audit_log'
RequestChannel = require './request_channel'
ResponseChannel = require './response_channel'
_ = require 'underscore'
require './util'

# The dispatcher accepts requests for keys and manages the
# dependencies between jobs. It ensures that the same work
# is never requested more than once, and makes sure jobs are
# re-run whenever their dependencies are met.
class Dispatcher

  # Initializer
  constructor: (options) ->
    @deps = {}
    @_test_mode = options.test_mode
    @_verbose = options.verbose
    @_idle_timeout = options.idle_timeout ? (if @_test_mode then 500 else 10000)
    @_audit_log = new AuditLog stream: options.audit
    {db_index} = options
    @_control_channel = new ControlChannel {db_index}
    @_requests_channel = new RequestChannel {db_index}
    @_responses_channel = new ResponseChannel {db_index}
    @_dependency_count = {}
    @_state = {}
    @_cycles = {}

  # Subscribe to the `requests` and `responses` channels.
  listen: ->
    @_requests_channel.listen (source, keys) => @_requested source, keys
    @_responses_channel.listen (ch, str) => @_responded str

  # Send quit signals to the work queues.
  quit: ->
    @_clear_timeout()
    @_control_channel.quit()
    finish = =>
      @_control_channel.delete_jobs()
      @_requests_channel.end()
      @_responses_channel.end()
      @_control_channel.end()
    setTimeout finish, 500

  # Provide a callback to be called when the dispatcher detects the process is stuck
  on_stuck: (@_stuck_callback) -> this

  # Set the idle handler
  on_idle: (@_idle_handler) -> this

  # Clear the timeout for idling
  _clear_timeout: ->
    clearTimeout @_timeout

  # Called when a worker requests keys. The keys requested are
  # recorded as dependencies, and any new key requests are
  # turned into new jobs. You can request the key `!reset` in
  # order to flush the dependency graph.
  _requested: (source, keys) ->
    if keys?.length
      @_new_request source, keys
    else if source == '!reset'
      @_reset()
    else
      @_seed source

  # The given key is a 'seed' request. In test mode, completion of
  # the seed request signals termination of the workers.
  _seed: (key) ->
    @_seed_key = key
    @_new_request '!seed', [key]

  # Forget everything we know about dependency state.
  _reset: ->
    @_dependency_count = {}
    @_state = {}
    @deps = {}
    @doc = null
    @_control_channel.reset()

  # Handle a request we've never seen before from a given source
  # job that depends on the given keys.
  _new_request: (source, keys) ->
    @_remove_all_deps source # XXX
    @_audit_log.request source, keys unless source == '!seed'
    @_reset_timeout()
    @_dependency_count[source] = 0
    @_handle_request source, keys

  # Reset the timer that checks if the process is broken
  _reset_timeout: ->
    @_clear_timeout()
    @_timeout = setTimeout (=> @_idle()), @_idle_timeout

  # Handle the requested keys by marking them as dependencies
  # and turning any unsatisfied ones into new jobs.
  _handle_request: (source, keys) ->
    for key in _.uniq keys
      # Mark the key as a dependency of the given source job. If
      # the key is already completed, then do nothing; if it has
      # not been previously requested, create a new job for it.
      unless @_state[key] == 'done'
        @_request_dependency key unless @_state[key]?
        (@deps[key] ?= []).push source
        @_dependency_count[source]++
    unless @_dependency_count[source]
      @_reschedule source

  # Take an unmet dependency from the latest request and push
  # it onto the `jobs` queue.
  _request_dependency: (req) ->
    @_state[req] = 'wait'
    @_control_channel.push_job req

  # Signal a job to run again by sending a resume message
  _reschedule: (key) ->
    delete @_dependency_count[key]
    return @_unseed() if key == '!seed'
    return if @_state[key] == 'done'
    @_control_channel.resume key

  # The seed request was completed. In test mode, quit the workers.
  _unseed: ->
    @_clear_timeout()
    @quit() if @_test_mode

  # Called when a key is completed. Any jobs depending on this
  # key are updated, and if they have no more dependencies, are
  # signalled to run again.
  _responded: (key) ->
    @_audit_log.response key
    @_state[key] = 'done'
    targets = @deps[key] ? []
    delete @deps[key]
    @_progress targets

  # Make progress on each of the given keys by decrementing
  # their count of remaining dependencies. When any reaches
  # zero, it is rescheduled.
  _progress: (keys) ->
    for key in keys
      unless --@_dependency_count[key]
        @_reschedule key

  # Activate a handler for idle timeouts. By default, this means
  # calling the doctor.
  _idle: ->
    if @_idle_handler
      @_idle_handler()
    else
      @_call_doctor()

  # Let the doctor figure out what's wrong here
  _call_doctor: ->
    console.log "Oops... calling the doctor!" if @_verbose
    @doc ?= new Doctor @deps, @_state, @_seed_key
    @doc.diagnose()
    if @doc.is_stuck()
      @doc.report() if @_verbose
      @_recover()
    else
      console.log "Hmm, the doctor couldn't find anything amiss..." if @_verbose

  # Recover from a stuck process.
  _recover: ->
    if @doc.recoverable()
      console.log 'trying to recover' # XXX
      for cycle in @doc.cycles
        console.log 'from', cycle # XXX
        return @_fail_recovery(cycle) if @_seen_cycle cycle
      for key, deps of @doc.cycle_dependencies()
        @_signal_worker_of_cycles key, deps
    else
      @_fail_recovery()

  # Determine if we've seen this cycle before
  _seen_cycle: (cycle) ->
    key = cycle.sort().join()
    return true if @_cycles[key]
    @_cycles[key] = true
    false

  # Recovery failed, let the callback know about it.
  _fail_recovery: (cycle) ->
    console.log 'oh shit', cycle # XXX
    @_stuck_callback?(@doc, @_control_channel.db())

  # Tell the given worker that they have cycle dependencies.
  _signal_worker_of_cycles: (key, deps) ->
    #@_remove_dependencies key, deps
    console.log 'sending cycle signal:', key, deps # XXX
    @_control_channel.cycle key, deps

  _remove_all_deps: (key) ->
    return unless @_dependency_count[key]?
    @_remove_dependencies key, @deps[key]

  # Remove given dependencies from the key
  _remove_dependencies: (key, deps) ->
    @_dependency_count[key] -= deps.length
    @deps[dep] = _.without @deps[dep], key for dep in deps

  # Print a debugging statement
  _debug: (args...) ->
    #console.log 'dispatcher:', args...

module.exports =

  # Create a new dispatcher instance and start it listening for
  # requests. Then return the dispatcher.
  run: (options) ->
    dispatcher = new Dispatcher(options ? {})
    dispatcher.listen()
    dispatcher
