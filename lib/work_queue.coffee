Worker = require './worker'
Dictionary = require './dictionary'
ControlFanout = require './control_fanout'
RequestFanout = require './request_fanout'
ResponseFanout = require './response_fanout'
JobQueue = require './job_queue'
events = require 'events'
consts = require './consts'

# The `WorkQueue` accepts job requests and starts `Worker` objects
# to handle them.
class WorkQueue extends events.EventEmitter

  # Register the 'next' event, and listen for 'resume' messages.
  constructor: (@options) ->
    {db_index} = @options
    @worker_dict = new Dictionary {db_index}
    @worker_request_fanout = new RequestFanout {db_index}
    @worker_response_fanout = new ResponseFanout {db_index}
    @runners = {}
    @mixins = {}
    @_job_queue = new JobQueue {db_index}
    @_control_fanout = new ControlFanout {db_index}
    @_workers = {}
    @_sticky = {}
    @_listen()
    @on 'next', => @_next()

  # Run the work queue, calling the given callback on completion
  run: (@callback) ->
    @_next()

  # Add a worker to the context
  worker: (prefix, runner) ->
    @runners[prefix] = runner

  # Mark the given worker as finished (release its memory)
  finish: (key) ->
    delete @_workers[key]

  # Alias for `Worker.mixin`
  mixin: (mixins) ->
    Worker.mixin mixins

  # Provide a callback to be executed in the context
  # of a worker whenever it has finished running, but before
  # saving its resutlts
  on_finish: (callback) ->
    Worker.finish_callback = callback
    this

  # Provide a callback to be called every time the worker begings running
  on_clear: (callback) ->
    Worker.clear_callback = callback
    this

  # Subscribe to channels
  _listen: ->
    @_control_fanout.listen (msg) => @_perform msg

  # React to a control message sent by the dispatcher
  _perform: (msg) ->
    [action, args...] = msg.split consts.key_sep
    switch action
      when 'resume' then @_resume args...
      when 'quit' then @_quit()
      when 'reset' then @_reset()
      when 'cycle' then @_cycle_detected args...

  # Resume the given worker (if it's one of ours)
  _resume: (key) ->
    @_workers[key]?.resume()

  # The dispatcher is telling us the given key is part of a cycle. If it's one
  # of ours, cause the worker to re-run, but throwing an error from the @get that
  # caused the cycle. On the plus side, we can assume that all the worker's non-
  # cycled dependencies have been met now.
  _cycle_detected: (key, dependencies...) ->
    @_workers[key]?.cycle_detected dependencies


  # Look for the next job using BLPOP on the "jobs" queue. This
  # will use an event emitter to call `next` again, so the stack
  # doesn't get large.
  # 
  # You can push the job `!quit` to make the work queue die.
  _next: ->
    @_job_queue.pop (err, [key, str]) =>
      if err
        @emit 'next'
        return @_error err
      try
        @_workers[str] = new Worker(str, this, @_sticky)
        @_workers[str].run()
      catch e
        @_error e unless e == 'no_runner'
      @emit 'next'

  # Shut down the redis connection and stop running workers
  _quit: ->
    @_job_queue.end()
    @_control_fanout.end()
    @worker_dict.end()
    @worker_request_fanout.end()
    @worker_response_fanout.end()
    @callback?()

  # Clean out the sticky cache
  _reset: ->
    console.log 'worker resetting'
    @_sticky = {}

  # Mark that a fatal exception occurred
  _error: (err) ->
    message = err.stack ? err
    console.log message
    @_job_queue.fatal message

  # Print a debugging statement
  _debug: (args...) ->
    #console.log 'queue:', args...

module.exports = WorkQueue
