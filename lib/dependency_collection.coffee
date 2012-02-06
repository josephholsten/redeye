consts = require './consts'
_ = require 'underscore'
require './util'

module.exports = class DependencyCollection
  constructor: ->
    @clear()
  clear: ->
    @_members = {}
  for: (key) ->
    @_members[key] ?= new DependencyRecord(key)

  states: ->
    states = {}
    for member, record of @_members
      states[member] = record.state unless record.is_new()
    states

  sources: ->
    sources = {}
    for key, record of @_members
      sources[key] = record.sources() if record.has_sources()
    sources

class DependencyRecord
  constructor: (@key) ->
    @count = 0
    @state = 'new'
    @_sources = []

  clear_targets: ->
    @count = 0
  add_target: (target) ->
    unless target.is_done()
      @count++
  remove_target: ->
    @count--
  remove_targets: (deps) ->
    @count -= deps.length

  has_targets: ->
    @count
  has_no_targets: ->
    !@has_targets()

  done: ->
    @state = 'done'
  wait: ->
    @state = 'wait'
  is_done: ->
    @state == 'done'
  is_wait: ->
    @state == 'wait'
  is_new: ->
    @state == 'new'

  add_source: (source) ->
    unless @is_done()
      @_sources.push source.key
  has_sources: ->
    @_sources.length != 0
  remove_source: (key) ->
    @_sources = _.without @_sources, key
  sources: ->
    @_sources

  mark_responded: ->
    @done()
    @clear_targets()

  is_seed_key: ->
    @key == consts.seed_key
