MAX_CANVAS_WIDTH = 32767
ONE_ON_ROOT_TWO = 1/Math.sqrt(2)

on_drop = (element, callback) ->
    
    $element = $(element)
    counter = 0

    update_counter = (num) ->
        counter = num
        if counter > 0
            $element.addClass('dragover')
        else
            $element.removeClass('dragover')

    $element.on 'dragenter', (event) ->
        update_counter counter + 1
        $element.addClass('dragover')

    $element.on 'dragleave', (event) ->
        update_counter counter - 1

    $element.on 'dragover', (event) ->
        event.preventDefault()

    $element.on 'dragend', (event) ->
        update_counter 0

    $element.on 'drop', (event) ->
        event.preventDefault()
        update_counter 0
        callback.apply this, arguments

get_channel_data = (file, callback) ->
    
    reader = new FileReader()
    reader.readAsArrayBuffer(file)
    console.log 'loading file', file
    reader.onloadend = ->
        console.log 'decoding file', file
        window.audio_context.decodeAudioData reader.result, (buffer) ->
            console.log 'done', buffer
            callback buffer.getChannelData(0)

convolve = (data, func, range = 8) ->
    
    response = for a in [-range...range]
        func(a) ? 0
    
    convolution = new Float32Array(data.length) # Initialises to 0
    
    for signal, signal_index in data

        continue if signal_index - range < 0
        continue if signal_index + range >= data.length

        for filter, filter_index in response
            convolution[signal_index] += data[signal_index + filter_index - range] * filter

    return convolution

combine = (data1, data2, func) ->

    result = new Float32Array(data1.length)

    for d, index in data1
        result[index] = func d, data2[index]

    return result

map = (data, func) ->
    
    result = new Float32Array(data.length)

    for d, i in data
        result[i] = func d

    return result

draw_line = (data, context, scale, detail, callback) ->

    chunk = 32
    index = 0

    interval = setInterval ->

        context.beginPath()
        context.moveTo (index-1)/detail, (data[index-1] ? 0) * scale

        for a in [index .. index + detail * chunk]
            context.lineTo a/detail, data[a] * scale

        context.stroke()

        index += detail * chunk

        if index >= data.length or index/detail > MAX_CANVAS_WIDTH
            clearInterval interval
            context.restore()
            callback?()

    , 0

draw_waveform = (data, { colour, detail, scale }, callback) ->

    colour ?= '#000'
    detail ?= 0.5
    scale ?= 256

    canvas = $('#waveform canvas')[0]
    canvas_width = Math.min MAX_CANVAS_WIDTH, Math.floor(data.length/detail)
    canvas.width = canvas_width if canvas.width != canvas_width

    context = canvas.getContext '2d'
    context.save()
    context.translate 0, 256
    context.scale 1, -1
    context.strokeStyle = colour

    draw_line data, context, scale, detail, callback

draw_frequencies = (data, { colour, detail, scale }, callback) ->

    colour = '#000'
    detail = 0.125
    scale = 16

    canvas = $('#frequencies canvas')[0]
    canvas_width = Math.min MAX_CANVAS_WIDTH, Math.floor(data.length/detail)
    canvas.width = canvas_width if canvas.width != canvas_width

    context = canvas.getContext '2d'
    context.save()
    context.translate 0, 512
    context.scale 1, -1
    context.strokeStyle = colour

    draw_line data, context, scale, detail, callback

# Perform a Fast Fourier Transform on an imaginary signal 'data'

fft = (data, from, count) ->
    
    half_count = count/2

    # Pre-compute the twiddle values for the recursion

    cache_real = new Float32Array(half_count)
    cache_imag = new Float32Array(half_count)

    for k in [0...half_count]
        angle = -2 * Math.PI * k/count
        cache_real[k] = Math.cos(angle)
        cache_imag[k] = Math.sin(angle)

    # Perform the transform recursively

    return fft_recurse data, from, count, 1, cache_real, cache_imag

# The recursive portion of the Fast Fourier Transform algorithm

fft_recurse = (data, from, count, step = 1, cache_real, cache_imag) ->

    # Check for the base case
    # TODO: Investigate placing the base case at a higher count than 1

    if count == 1
        return [ new Float32Array([ data[0][from] ]), new Float32Array([ data[1][from] ]) ]

    half_count = count/2

    # Recurse

    [ first_half_real, first_half_imag ] = fft_recurse(data, from, half_count, step*2, cache_real, cache_imag)
    [ second_half_real, second_half_imag ] = fft_recurse(data, from + step, half_count, step*2, cache_real, cache_imag)

    # Combine the two results together using the twiddle factors

    result_real = new Float32Array(count)
    result_imag = new Float32Array(count)

    for k in [0...half_count]

        # Fetch the twiddle factor from the pre-computed values

        real = cache_real[k*step]
        imag = cache_imag[k*step]

        # Multiply the twiddle factor with the odd transform

        rr = real * second_half_real[k]
        ri = real * second_half_imag[k]
        ir = imag * second_half_real[k]
        ii = imag * second_half_imag[k]

        # Add the result to the even transform

        result_real[k] = (first_half_real[k] + rr - ii) * ONE_ON_ROOT_TWO
        result_imag[k] = (first_half_imag[k] + ri + ir) * ONE_ON_ROOT_TWO

        # Use a shortcut to easily calculate the second half of the results

        result_real[k+half_count] = (first_half_real[k] - (rr - ii)) * ONE_ON_ROOT_TWO
        result_imag[k+half_count] = (first_half_imag[k] - (ri + ir)) * ONE_ON_ROOT_TWO

    return [ result_real, result_imag ]

imaginary = (data) -> [ data, new Float32Array(data.length) ]

time = (message, func) ->
    console.log "Starting #{message}"
    begin = Date.now()
    func()
    console.log "#{message} took #{Date.now() - begin}"

tick = (func) -> setTimeout func, 0

call_listener = (listener, args) -> tick ->

    listener.apply {
        callback: -> listener.promise.do.apply this, arguments
    }, args

promise = ->

    done = false
    listeners = []
    args = []
    
    return {

        then: (listener) ->

            listener.promise = promise()

            if done
                call_listener listener, args
            else
                listeners.push listener

            return listener.promise

        then_do: (listener) ->
            @then ->
                listener.apply this, arguments
                @callback.apply this, arguments

        do: ->

            args = arguments

            for listener in listeners
                call_listener listener, args

            done = true
            listeners = []

            return this
    }

begin = -> promise().do()

hilbert_transform = (x) -> if x % 2 == 0 then 0 else 1/(Math.PI*x)
modulus = (a, b) -> Math.sqrt a*a + b*b

test = ->

    # test = ( (if a == 0 then 1 else Math.sin(2*Math.PI*a/8)/(2*Math.PI*a/8)) for a in [-512*1024...512*1024] )
    test = ( (if a == 0 then 1 else Math.sin(2*Math.PI*a/8)/(2*Math.PI*a/8)) for a in [-512...512] )
    # test = [ 0, 1, 0, -1, 0, 1, 0, -1 ]

    wave_draw = begin().then ->
        draw_waveform test, colour: 'rgba(0, 0, 0, 0.5)', detail: 0.5, @callback

    [ convolution, envelope, test_real, test_imag, test_freq ] = []

    begin().then_do ->
        time 'convolving...', ->
            convolution = convolve test, hilbert_transform

    .then_do ->
        time 'enveloping...', ->
            envelope = combine test, convolution, modulus

    .then_do ->
        wave_draw = wave_draw.then ->
            draw_waveform envelope, colour: 'rgba(0, 0, 255, 0.5', detail: 0.5, @callback
    
    .then_do ->
        time 'fft transform', ->
            [ test_real, test_imag ] = fft(imaginary(test), 0, test.length)

    .then_do ->
        time 'modulus', ->
            test_freq = combine test_real, test_imag, modulus

    .then_do ->
        wave_draw = wave_draw.then ->
            draw_frequencies test_freq, colour: 'rgba(0, 0, 0, 0.5)', detail: 0.5, @callback

    .then_do ->
        time 'find max', ->
            max = Array.prototype.slice.call(test_freq).reduce (max, a, index) ->
                if max[0] >= a
                    return max
                else
                    return [ a, index ]
            , [ 0, 0 ]
            console.log 'max:', max

    .then_do ->
        time 'fft transform 2', ->
            [ test_imag, test_real ] = fft([ test_imag, test_real ], 0, test.length)

    .then_do ->
        wave_draw = wave_draw.then ->
            draw_waveform test_real, colour: 'rgba(255, 0, 0, 0.5)', detail: 0.5, @callback

    .then_do -> wave_draw.then_do -> console.log 'all done'

$ ->

    window.audio_context = new AudioContext()

    test()

    on_drop '#drop-zone', (event) ->

        draw_queue = begin()

        for file in event.originalEvent.dataTransfer.files

            [ data, convolution, envelope, transform_real, transform_imag, frequencies ] = []

            begin().then ->
                get_channel_data file, @callback

            .then_do (channel_data) ->
                data = channel_data

            .then_do ->
                draw_queue = draw_queue.then ->
                    draw_waveform data, colour: 'rgba(0, 0, 0, 0.15)', @callback

            .then_do ->
                console.log 'convolving...'
                convolution = convolve data, hilbert_transform

            .then_do ->
                console.log 'enveloping...'
                envelope = combine data, convolution, modulus

            .then_do ->
                draw_queue = draw_queue.then ->
                    draw_waveform envelope, colour: 'rgba(255, 0, 0, 0.15)', @callback

            .then_do ->
                console.log 'transforming...'
                [ transform_real, transform_imag ] = fft(imaginary(envelope), 1024*1024, 1024*1024)

            .then_do ->
                console.log 'absoluting...'
                frequencies = combine transform_real, transform_imag, modulus

            .then_do ->
                console.log 'finding spike...'
                sample = Array.prototype.slice.call(frequencies)[0..120]
                spike = sample[12..].reduce (max, val, index) ->
                    if max[0] >= val
                        return max
                    else
                        return [ val, index + 12 ]
                , [ 0, 0 ]
                console.log 'spike:', spike
                console.log sample

            .then_do ->
                draw_queue = draw_queue.then ->
                    draw_frequencies frequencies, colour: 'rgba(0, 0, 0, 1)', @callback

            .then_do -> draw_queue.then_do -> console.log 'all done'

        return
