# The Doctor scans the dependencies and state of requests to determine
# why no progress is being made. It looks for cyclic dependencies and
# plain unsatisfied dependencies, and can report them.
class Doctor

  # Create a new doctor based on the given dependencies
  # (in `{dependency: [dependent, ...]}` form), state of jobs,
  # and the seed job.
  constructor: (@deps, @state, @seed) ->

  # Scan the information to determine what's wrong
  diagnose: ->
    @clear()
    @invert_deps()
    @scan @seed

  # Print a report about what's broken
  report: ->
    # @report_deps()
    # @report_state()
    @report_loose_ends()
    @report_cycles()
  
  # Print out the dependencies
  report_deps: ->
    for key, values of @inv
      console.log "#{key} -> #{values.join ', '}"
  
  # Report on the state of affairs
  report_state: ->
    for key, state of @state
      console.log "#{key} :: #{state}"
  
  # Print out a list of cyclic dependencies. For instance,
  # 
  #     A -> B -> C
  # 
  # means that C cycles back around to A.
  report_cycles: ->
    return unless @cycles.count
    console.log "Cycles:"
    for cycle in @cycles
      console.log "  #{cycle.join ' -> '}"
  
  # Report on loose ends, that is, unsatisfied dependencies that
  # aren't part of cycles.
  report_loose_ends: ->
    return unless @loose_ends.length
    console.log "Loose ends: #{@loose_ends.join(', ')}"

  # Reset the doctor's diagnosis for another run.
  clear: ->
    @inv = {}
    @cycles = []
    @loose_ends = []
    @_loose_ends = {}
    @stack = []

  # Recursive scanning method. Simultaneously determines
  # cycles and graph leaves.
  scan: (node) ->
    if node in @stack
      @cycles.push @stack[0..-1]
      return
    @stack.push node
    nexts = @inv[node] ? []
    for next in nexts
      @scan next
    unless nexts.length
      unless @state[node] == 'done'
        @add_loose_end node
    @stack.pop()
  
  add_loose_end: (node) ->
    return if @_loose_ends[node]
    @_loose_ends[node] = true
    @loose_ends.push node

  # Convert the input form of dependencies to a more straightforward version.
  # For instance, it converts
  # 
  #     {'A': ['B', 'C'], 'B': ['C']}
  # 
  # to
  # 
  #     {'B': ['A'], 'C': ['A', 'B']}
  invert_deps: ->
    for source, targets of @deps
      for target in targets
        sources = (@inv[target] ?= [])
        sources.push source

module.exports = Doctor