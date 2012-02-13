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
    @_test_mode = options.test_mode
    @_verbose = options.verbose
    @_idle_timeout = options.idle_timeout ? (if @_test_mode then 500 else 10000)
    @_audit_log = new AuditLog stream: options.audit
    {db_index} = options
    @_control_channel = new ControlChannel {db_index}
    @_requests_channel = new RequestChannel {db_index}
    @_responses_channel = new ResponseChannel {db_index}
    @needs = {}
    @gives = {}
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
    @needs = {}
    @gives = {}
    @doc = null
    @_control_channel.reset()

  # Handle a request we've never seen before from a given source
  # job that depends on the given keys.
  _new_request: (source, keys) ->
    @_audit_log.request source, keys unless source == '!seed'
    key = keys[0] # XXX move this up the chain
    @_reset_timeout()
    @_handle_request source, key

  # Reset the timer that checks if the process is broken
  _reset_timeout: ->
    @_clear_timeout()
    @_timeout = setTimeout (=> @_idle()), @_idle_timeout

  _handle_request: (source, key) ->
    if dep = @needs[source]
      @gives[dep] = _.without @gives[dep], source
    if @_state[key] == 'done'
      @_reschedule source
    else
      @_request_dependency key unless @_state[key]?
      (@gives[key] ?= []).push source
      @needs[source] = key

  # Take an unmet dependency from the latest request and push
  # it onto the `jobs` queue.
  _request_dependency: (req) ->
    @_state[req] = 'wait'
    @_control_channel.push_job req

  # Signal a job to run again by sending a resume message
  _reschedule: (key) ->
    delete @needs[key]
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
    delete @needs[key]
    targets = @gives[key] ? []
    delete @gives[key]
    @_progress key, targets

  # Make progress on each of the given keys by decrementing
  # their count of remaining dependencies. When any reaches
  # zero, it is rescheduled.
  _progress: (dep, keys) ->
    for key in keys
      @_reschedule key if @needs[key] == dep
  
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
    @doc ?= new Doctor @gives, @_state, @_seed_key
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
        return @_fail_recovery(cycle) if @_seen_cycle cycle
      for key, deps of @doc.cycle_dependencies()
        @_signal_worker_of_cycles key, deps
      @_reset_timeout()
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
    @_stuck_callback?(@doc, @_control_channel.db())

  # Tell the given worker that they have cycle dependencies.
  _signal_worker_of_cycles: (key, deps) ->
    @_control_channel.cycle key, deps

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
