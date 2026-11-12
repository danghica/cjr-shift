"""JSON-to-native representation conversion, without working-time calculations."""
import json
from pathlib import Path

MAX_MINUTE = 6000000000

def boolean(value):
    if type(value) is not bool:
        raise ValueError('working-time flags must be JSON booleans')
    return 'true' if value else 'false'

def number(value):
    if type(value) is not int or not 0 <= value <= MAX_MINUTE:
        raise ValueError('expected a nonnegative integer within working-time representation bounds')
    return str(value)

def minute(value):
    if isinstance(value, str) and '~' not in value and ',' not in value and ';' not in value:
        return value
    if type(value) is int:
        return '@' + number(value)
    raise ValueError('expected a timestamp string or ordinal minute integer')

def intervals(value):
    if not isinstance(value, list) or len(value) > 10000:
        raise ValueError('intervals must be a list containing at most 10000 pairs')
    rows = []
    for pair in value:
        if not isinstance(pair, list) or len(pair) != 2:
            raise ValueError('each interval must have a start and end')
        rows.append(','.join(map(minute, pair)))
    return '-|' + ';'.join(rows)

def encode_metadata(path):
    with Path(path).open() as handle:
        data = json.load(handle)
    required = {'jurisdiction','adult','ordinaryRegime','coverageStart','coverageEnd',
                'periodCoverageComplete','elapsedWorkKnown','otherWork','normalWork',
                'weeklyRest','nightWork','periods'}
    if not isinstance(data, dict) or set(data) != required:
        raise ValueError('metadata keys must be exactly: ' + ', '.join(sorted(required)))
    if data['jurisdiction'] not in ('GB','NI','unknown'):
        raise ValueError('jurisdiction must be GB, NI, or unknown')
    values = [str({'unknown':0,'GB':1,'NI':2}[data['jurisdiction']]), boolean(data['adult']), boolean(data['ordinaryRegime']),
              minute(data['coverageStart']), minute(data['coverageEnd']), boolean(data['periodCoverageComplete']), boolean(data['elapsedWorkKnown'])]
    values += [intervals(data[key]) for key in ('otherWork','normalWork','weeklyRest','nightWork')]
    periods = data['periods']
    if not isinstance(periods, list) or len(periods) > 10000:
        raise ValueError('periods must be a list of at most 10000 assessment periods')
    encoded=[]
    keys={'rule','start','end','calendarMinutes','extraStart','extraEnd','evidence','restScheme','dailyRestOverlap'}
    for period in periods:
        if not isinstance(period,dict) or set(period)!=keys:
            raise ValueError('each assessment period requires: '+', '.join(sorted(keys)))
        if not isinstance(period['evidence'], str):
            raise ValueError('assessment evidence must be a string')
        evidence={'unknown':0,'known':1,'not_applicable':2,'unsupported':3}.get(period['evidence'])
        if evidence is None:
            raise ValueError('unknown assessment evidence status')
        encoded.append(','.join([number(period['rule']), minute(period['start']), minute(period['end']),
            number(period['calendarMinutes']),minute(period['extraStart']),minute(period['extraEnd']),str(evidence),
            number(period['restScheme']),boolean(period['dailyRestOverlap'])]))
    return '~'.join(values+[';'.join(encoded)])
