consts = require './consts'
Doctor = require './doctor'
ControlChannel = require './control_channel'
AuditLog = require './audit_log'
RequestChannel = require './request_channel'
ResponseChannel = require './response_channel'
DependencyCollection = require './dependency_collection'
_ = require 'underscore'
require './util'

# The dispatcher accepts requests for keys and manages the
# dependencies between jobs. It ensures that the same work
# is never requested more than once, and makes sure jobs are
# re-run whenever their dependencies are met.
class Dispatcher

  # Initializer
  constructor: (options) ->
    @_test_mode = options.test_mode
    @_verbose = options.verbose
    @_idle_timeout = options.idle_timeout ? (if @_test_mode then 500 else 10000)
    @_audit_log = new AuditLog stream: options.audit
    {db_index} = options
    @_control_channel = new ControlChannel {db_index}
    @_requests_channel = new RequestChannel {db_index}
    @_responses_channel = new ResponseChannel {db_index}
    @_dependencies = new DependencyCollection()
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
  _requested: (source_key, target_keys) ->
    if target_keys?.length
      @_audit_log.request source_key, target_keys
      @_new_request source_key, target_keys
    else if source_key == consts.reset_key
      # Forget everything we know about dependency state.
      @_dependencies.clear()
      @_control_channel.reset()
    else
      # The given key is a 'seed' request. In test mode, completion of
      # the seed request signals termination of the workers.
      @_seed_key = source_key
      @_new_request consts.seed_key, [source_key]

  # Handle a request we've never seen before from a given source
  # job that depends on the given keys.
  _new_request: (source_key, target_keys) ->
    # Reset the timer that checks if the process is broken
    @_clear_timeout()
    @_timeout = setTimeout (=> @_idle()), @_idle_timeout
    source = @_dependencies.for source_key
    source.clear_targets()
    # Handle the requested keys by marking them as dependencies
    # and turning any unsatisfied ones into new jobs.
    for target_key in _.uniq target_keys
      target = @_dependencies.for target_key
      source.add_target target
      target.add_source source
      # Mark the key as a dependency of the given source job. If
      # the key is already completed, then do nothing; if it has
      # not been previously requested, create a new job for it.
      if target.is_new()
        # Take an unmet dependency from the latest request and push
        # it onto the `jobs` queue.
        target.wait()
        @_control_channel.push_job target.key
    @_reschedule source

  # Signal a job to run again by sending a resume message.
  _reschedule: (source) ->
    if source.has_no_targets()
      if source.is_seed_key()
        # The seed request was completed. In test mode, quit the workers.
        @_clear_timeout()
        @quit() if @_test_mode
      else
        @_control_channel.resume source.key unless source.is_done()

  # Called when a key is completed. Any jobs depending on this
  # key are updated, and if they have no more dependencies, are
  # signalled to run again.
  _responded: (target_key) ->
    target = @_dependencies.for target_key
    @_audit_log.response target.key
    target.done()
    target.clear_targets()
    # Make progress on each of the given keys by decrementing
    # their count of remaining dependencies. When any reaches
    # zero, it is rescheduled.
    for source_key in target.sources()
      source = @_dependencies.for source_key
      source.remove_target target
      @_reschedule source

  # Activate a handler for idle timeouts. By default, this means
  # calling the doctor.
  _idle: ->
    if @_idle_handler
      @_idle_handler()
    else
      @_call_doctor()

  _call_doctor: ->
    console.log "Oops... calling the doctor!" if @_verbose
    @doc ?= new Doctor @_dependencies.sources(), @_dependencies.states(), @_seed_key
    @doc.deps = @_dependencies.sources()
    @doc.diagnose()
    if @doc.is_stuck()
      @doc.report() if @_verbose
      @_recover()
    else
      console.log "Hmm, the doctor couldn't find anything amiss..." if @_verbose

  # Recover from a stuck process.
  _recover: ->
    if @doc.recoverable()
      for cycle in @doc.cycles
        return @_fail_recovery() if @_seen_cycle cycle
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
  _fail_recovery: ->
    @_stuck_callback?(@doc, @_control_channel.db())

  # Tell the given worker that they have cycle dependencies.
  _signal_worker_of_cycles: (source, targets) ->
    @_dependencies.for(source).remove_targets targets
    @_dependencies.for(target).remove_source source for target in targets
    @_control_channel.cycle source, targets

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
