###
Copyright (c) 2013-2014, Regents of the University of California
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  1. Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
  2. Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
###

# used to put prefixes before headers
exports.requirePatientView = (req) ->
  keyType = req.path[req.path.length - 1]
  if not (req.path.length is 6 and keyType is 'patient')
    throw new Error('You may only dump the patient view')

# use with start() to print headers: start(headers: csvHeaders('my-report'))
exports.csvHeaders = (reportName) ->
  'Content-Disposition': (
    "attachment; filename=\"#{reportName}-#{today()}.csv"),
  'Content-Type': 'text/csv'


# current date (ISO format), for report name
exports.today = today = ->
  (new Date()).toISOString()[..9]


exports.VERSION_HEADER = 'version'

# get version from task
exports.getVersion = (task) ->
  task.version ? null

exports.DATE_HEADER = 'date'

# get date from task (ISO version)
exports.getDate = (task) ->
  timestamp = task.limitedPHI?.clockOffset
  if timestamp?
    # note that this the server's local time
    (new Date(timestamp)).toISOString()[..9]
  else
    null


exports.DATA_QUALITY_HEADERS = [
  'goodForResearch', 'qualityIssues', 'adminComments']

# get data quality values from task
exports.getDataQualityCols = (encounter) ->
  notes = encounter.administrationNotes
  goodForResearch = null
  if notes?.goodForResearch?  # use 0/1 rather than false/true
    goodForResearch = Number(notes.goodForResearch)
  qualityIssues = (notes?.qualityIssues ? []).join(', ')
  adminComments = notes?.comments ? null

  return [goodForResearch, qualityIssues, adminComments]
