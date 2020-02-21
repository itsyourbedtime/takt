// CroneEngine_Timber
//
// v1.0.0 Beta 6 Mark Eats

Engine_Timber_Takt : CroneEngine {

	var maxVoices = 7;
	var maxSamples = 101;
	var killDuration = 0.003;
	var waveformDisplayRes = 40;

	var voiceGroup;
	var voiceList;
	var samples;
	var replyFunc;

	var players;
	var synthNames;
	var lfos;
	var mixer;
	var reverb;
	var delay;

	var lfoBus;
	var fxBus;
	var reverbBus;
	var mixerBus;
	var sidechainBus;

	var loadQueue;
	var loadingSample = -1;

	var generateWaveformsOnLoad = true;
	var scriptAddress;
	var waveformQueue;
	var waveformRoutine;
	var generatingWaveform = -1;
	var abandonCurrentWaveform = false;

	var pitchBendAllRatio = 1;
	var pressureAll = 0;

	var defaultSample;

	// var debugBuffer;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}
	

	alloc {

		// debugBuffer = Buffer.alloc(context.server, context.server.sampleRate * 4, 5);

		defaultSample = (

			streaming: 0,
			buffer: nil,
			path: nil,

			channels: 0,
			sampleRate: 0,
			reverbSend: -99,
			delaySend: -99,
			sidechainSend: -99,
			numFrames: 0,

			transpose: 0,
			detuneCents: 0,
			pitchBendRatio: 1,
			pressure: 0,

			lfo1Fade: 0,
			lfo2Fade: 0,

			startFrame: 0,
			endFrame: 0,
			playMode: 0,
			loopStartFrame: 0,
			loopEndFrame: 0,

			freqModLfo1: 0,
			freqModLfo2: 0,
			freqModEnv: 0,

			ampAttack: 0,
			ampDecay: 1,
			ampSustain: 1,
			ampRelease: 0.003,

			modAttack: 1,
			modDecay: 2,
			modSustain: 0.65,
			modRelease: 1,

			downSampleTo: 48000,
			bitDepth: 24,

			filterFreq: 20000,
			filterReso: 0,
			filterType: 0,
			filterTracking: 1,
			filterFreqModLfo1: 0,
			filterFreqModLfo2: 0,
			filterFreqModEnv: 0,
			filterFreqModVel: 0,
			filterFreqModPressure: 0,

			pan: 0,
			panModLfo1: 0,
			panModLfo2: 0,
			panModEnv: 0,
			amp: 0,
			ampModLfo1: 0,
			ampModLfo2: 0,
		);

		voiceGroup = Group.new(context.xg);
		voiceList = List.new();

		lfoBus = Bus.control(context.server, 2);
		mixerBus = Bus.audio(context.server, 2);
		sidechainBus = Bus.audio(context.server, 2);
		fxBus = Bus.audio(context.server, 2);
		reverbBus = Bus.audio(context.server, 2);
		players = Array.newClear(4);

		loadQueue = Array.new(maxSamples);
		scriptAddress = NetAddr("localhost", 10111);
		waveformQueue = Array.new(maxSamples);

		// Receive messages from server
		replyFunc = OSCFunc({
			arg msg;
			var id = msg[2];
			scriptAddress.sendBundle(0, ['/enginePlayPosition', msg[3].asInt, msg[4].asInt, msg[5]]);
		}, path: '/replyPlayPosition', srcID: context.server.addr);

		// Sample defaults
		samples = Array.fill(maxSamples, { defaultSample.deepCopy; });

		// Buffer players
		2.do({
			arg i;
			players[i] = {
				arg freqRatio = 1, sampleRate, gate, playMode, voiceId, sampleId, bufnum, numFrames, startFrame, i_lockedStartFrame, endFrame, loopStartFrame, loopEndFrame;

				var signal, progress, phase, offsetPhase, direction, rate, phaseStart, phaseEnd,
				firstFrame, lastFrame, shouldLoop, inLoop, loopEnabled, loopInf, duckDuration, duckNumFrames, duckNumFramesShortened, duckGate, duckControl;

				firstFrame = startFrame.min(endFrame);
				lastFrame = startFrame.max(endFrame);

				loopEnabled = InRange.kr(playMode, 0, 1);
				loopInf = InRange.kr(playMode, 1, 1);

				direction = (endFrame - startFrame).sign;
				rate = freqRatio * BufRateScale.ir(bufnum) * direction;

				progress = (Sweep.ar(1, SampleRate.ir * rate) + i_lockedStartFrame).clip(firstFrame, lastFrame);

				shouldLoop = loopEnabled * gate.max(loopInf);

				inLoop = Select.ar(direction > 0, [
					progress < (loopEndFrame - 40), // NOTE: This tiny offset seems odd but avoids some clicks when phasor start changes
					progress > (loopStartFrame + 40)
				]);
				inLoop = PulseCount.ar(inLoop).clip * shouldLoop;

				phaseStart = Select.ar(inLoop, [
					K2A.ar(i_lockedStartFrame),
					K2A.ar(loopStartFrame)
				]);
				// Let phase run over end so it is caught by FreeSelf below. 150 is chosen to work even with drastic re-pitching.
				phaseEnd = Select.ar(inLoop, [
					K2A.ar(endFrame + (BlockSize.ir * 150 * direction)),
					K2A.ar(loopEndFrame)
				]);

				phase = Phasor.ar(trig: 0, rate: rate, start: phaseStart, end: phaseEnd, resetPos: 0);

				// Free if reached end of sample
				FreeSelf.kr(Select.kr(direction > 0, [
					phase < firstFrame,
					phase > lastFrame
				]));

				SendReply.kr(trig: Impulse.kr(15), cmdName: '/replyPlayPosition', values: [sampleId, voiceId, (phase / numFrames).clip]);

				signal = BufRd.ar(numChannels: i + 1, bufnum: bufnum, phase: phase, interpolation: 2);

				// Duck across loop points and near start/end to avoid clicks (3ms * 2, playback time)
				duckDuration = 0.003;
				duckNumFrames = duckDuration * BufSampleRate.ir(bufnum) * freqRatio * BufRateScale.ir(bufnum);

				// Start (these also mute one-shots)
				duckControl = Select.ar(firstFrame > 0, [
					phase.linlin(firstFrame, firstFrame + 1, 0, 1),
					phase.linlin(firstFrame, firstFrame + duckNumFrames, 0, 1)
				]);

				// End
				duckControl = duckControl * Select.ar(lastFrame < numFrames, [
					phase.linlin(lastFrame - 1, lastFrame, 1, 0),
					phase.linlin(lastFrame - duckNumFrames, lastFrame, 1, 0)
				]);

				duckControl = duckControl.max(inLoop);

				duckNumFramesShortened = duckNumFrames.min((loopEndFrame - loopStartFrame) * 0.45);
				duckDuration = (duckNumFramesShortened / duckNumFrames) * duckDuration;
				duckNumFrames = duckNumFramesShortened;

				duckGate = Select.ar(direction > 0, [
					InRange.ar(phase, loopStartFrame, loopStartFrame + duckNumFrames),
					InRange.ar(phase, loopEndFrame - duckNumFrames, loopEndFrame)
				]) * inLoop;

				duckControl = duckControl * EnvGen.ar(Env.new([1, 0, 1], [A2K.kr(duckDuration)], \linear, nil, nil), duckGate);

				signal = signal * duckControl;
			};
		});

		// Streaming players
		2.do({
			arg i;
			players[i + 2] = {
				arg freqRatio = 1, sampleRate, gate, playMode, voiceId, sampleId, bufnum, numFrames, i_lockedStartFrame, endFrame, loopStartFrame, loopEndFrame;
				var signal, rate, progress, loopEnabled, oneShotActive, duckDuration, duckControl;

				loopEnabled = InRange.kr(playMode, 0, 1);

				rate = (sampleRate / SampleRate.ir) * freqRatio;

				signal = VDiskIn.ar(numChannels: i + 1, bufnum: bufnum, rate: rate, loop: loopEnabled);

				progress = Sweep.ar(1, SampleRate.ir * rate) + i_lockedStartFrame;
				progress = Select.ar(loopEnabled, [progress.clip(0, endFrame), progress.wrap(0, numFrames)]);

				SendReply.kr(trig: Impulse.kr(15), cmdName: '/replyPlayPosition', values: [sampleId, voiceId, progress / numFrames]);

				// Ducking
				duckDuration = 0.003 * sampleRate * rate.reciprocal;

				// Start
				duckControl = Select.ar(i_lockedStartFrame > 0, [
					K2A.ar(1),
					progress.linlin(i_lockedStartFrame, i_lockedStartFrame + duckDuration, 0, 1) + (progress < i_lockedStartFrame)
				]);

				// End
				duckControl = duckControl * Select.ar(endFrame < numFrames, [
					progress.linlin(endFrame, endFrame + 1, 1, loopEnabled),
					progress.linlin(endFrame - duckDuration, endFrame, 1, loopEnabled)
				]);

				// Duck at end of stream if loop is enabled and startFrame > 0
				duckControl = duckControl * Select.ar(loopEnabled * (i_lockedStartFrame > 0), [
					K2A.ar(1),
					progress.linlin(numFrames - duckDuration, numFrames, 1, 0)
				]);

				// One shot freer
				FreeSelf.kr((progress >= endFrame) * (1 - loopEnabled));

				signal = signal * duckControl;
			};
		});


		// SynthDefs
		
		lfos = SynthDef(\lfos, {
			arg out, lfo1Freq = 2, lfo1WaveShape = 0, lfo2Freq = 4, lfo2WaveShape = 3;
			var lfos, i_controlLag = 0.005;

			var lfoFreqs = [Lag.kr(lfo1Freq, i_controlLag), Lag.kr(lfo2Freq, i_controlLag)];
			var lfoWaveShapes = [lfo1WaveShape, lfo2WaveShape];

			lfos = Array.fill(2, {
				arg i;
				var lfo, lfoOscArray = [
					SinOsc.kr(lfoFreqs[i]),
					LFTri.kr(lfoFreqs[i]),
					LFSaw.kr(lfoFreqs[i]),
					LFPulse.kr(lfoFreqs[i], mul: 2, add: -1),
					LFNoise0.kr(lfoFreqs[i])
				];
				lfo = Select.kr(lfoWaveShapes[i], lfoOscArray);
				lfo = Lag.kr(lfo, 0.005);
			});

			Out.kr(out, lfos);

		}).play(target:context.xg, args: [\out, lfoBus], addAction: \addToHead);


		synthNames = Array.with(\monoBufferVoice, \stereoBufferVoice, \monoStreamingVoice, \stereoStreamingVoice);
		synthNames.do({

			arg name, i;

			SynthDef(name, {

				arg out, reverbSendBus, delaySendBus, sidechainSendBus, sampleRate, freq, transposeRatio, detuneRatio = 1, pitchBendRatio = 1, pitchBendSampleRatio = 1, playMode = 0, gate = 0, killGate = 1, vel = 1, pressure = 0, pressureSample = 0, amp = 1,
				lfos, lfo1Fade, lfo2Fade, freqModLfo1, freqModLfo2, freqModEnv, 
				ampAttack, ampDecay, ampSustain, ampRelease, modAttack, modDecay, modSustain, modRelease,
				downSampleTo, bitDepth, reverbSend, delaySend, sidechainSend,
				filterFreq, filterReso, filterType, filterTracking, filterFreqModLfo1, filterFreqModLfo2, filterFreqModEnv, filterFreqModVel, filterFreqModPressure,
				pan, panModLfo1, panModLfo2, panModEnv, ampModLfo1, ampModLfo2;

				var i_nyquist = SampleRate.ir * 0.5, i_cFreq = 48.midicps, i_origFreq = 60.midicps, signal, freqRatio, freqModRatio, filterFreqRatio,
				killEnvelope, ampEnvelope, modEnvelope, lfo1, lfo2, i_controlLag = 0.005;

				// Lag inputs
				detuneRatio = Lag.kr(detuneRatio * pitchBendRatio * pitchBendSampleRatio, i_controlLag);
				pressure = Lag.kr(pressure + pressureSample, i_controlLag);
				amp = Lag.kr(amp, i_controlLag);
				filterFreq = Lag.kr(filterFreq, i_controlLag);
				filterReso = Lag.kr(filterReso, i_controlLag);
				pan = Lag.kr(pan, i_controlLag);

				// LFOs
				lfo1 = Line.kr(start: (lfo1Fade < 0), end: (lfo1Fade >= 0), dur: lfo1Fade.abs, mul: In.kr(lfos, 1));
				lfo2 = Line.kr(start: (lfo2Fade < 0), end: (lfo2Fade >= 0), dur: lfo2Fade.abs, mul: In.kr(lfos, 2)[1]);

				// Envelopes
				gate = gate.max(InRange.kr(playMode, 3, 3)); // Ignore gate for one shots
				killGate = killGate + Impulse.kr(0); // Make sure doneAction fires
				killEnvelope = EnvGen.ar(envelope: Env.asr(0, 1, killDuration), gate: killGate, doneAction: Done.freeSelf);
				ampEnvelope = EnvGen.ar(envelope: Env.adsr(ampAttack, ampDecay, ampSustain, ampRelease), gate: gate, doneAction: Done.freeSelf);
				modEnvelope = EnvGen.ar(envelope: Env.adsr(modAttack, modDecay, modSustain, modRelease), gate: gate);

				// gate.poll(8, "gate");
				// killGate.poll(8, "killGate");
				// ampEnvelope.poll(8, "ampEnvelope");

				// Freq modulation
				freqModRatio = 2.pow((lfo1 * freqModLfo1) + (lfo2 * freqModLfo2) + (modEnvelope * freqModEnv));
				freq = freq * transposeRatio * detuneRatio;
				freq = (freq * freqModRatio).clip(20, i_nyquist);
				freqRatio = (freq / i_origFreq) * 1;

				// Player
				signal = SynthDef.wrap(players[i], [\kr, \kr, \kr, \kr], [freqRatio, sampleRate, gate, playMode]);

				// Downsample and bit reduction
				if(i > 1, { // Streaming
					downSampleTo = downSampleTo.min(sampleRate);
				}, {
					downSampleTo = Select.kr(downSampleTo >= sampleRate, [
						downSampleTo,
						downSampleTo = context.server.sampleRate
					]);
				});
				signal = Decimator.ar(signal, downSampleTo, bitDepth);

				// 12dB LP/HP filter
				filterFreqRatio = Select.kr((freq < i_cFreq), [
					i_cFreq + ((freq - i_cFreq) * filterTracking),
					i_cFreq - ((i_cFreq - freq) * filterTracking)
				]);
				filterFreqRatio = filterFreqRatio / i_cFreq;
				filterFreq = filterFreq * filterFreqRatio;
				filterFreq = filterFreq * ((48 * lfo1 * filterFreqModLfo1) + (48 * lfo2 * filterFreqModLfo2) + (96 * modEnvelope * filterFreqModEnv) + (48 * vel * filterFreqModVel) + (48 * pressure * filterFreqModPressure)).midiratio;
				filterFreq = filterFreq.clip(20, 20000);
				filterReso = filterReso.linlin(0, 1, 1, 0.02);
				signal = Select.ar(filterType, [
					RLPF.ar(signal, filterFreq, filterReso),
					RHPF.ar(signal, filterFreq, filterReso)
				]);

				// Panning
				pan = (pan + (lfo1 * panModLfo1) + (lfo2 * panModLfo2) + (modEnvelope * panModEnv)).clip(-1, 1);
				signal = Splay.ar(inArray: signal, spread: 1 - pan.abs, center: pan);

				// Amp
				signal = signal * lfo1.range(1 - ampModLfo1, 1) * lfo2.range(1 - ampModLfo2, 1) * ampEnvelope * killEnvelope * vel.linlin(0, 1, 0.1, 1);
				signal = tanh(signal * amp.dbamp * (1 + pressure)).softclip;
				Out.ar(out, signal);
				Out.ar(sidechainSendBus, signal * sidechainSend.dbamp);
				Out.ar(delaySendBus, signal * delaySend.dbamp);
				Out.ar(reverbSendBus, signal * reverbSend.dbamp);
			}).add;
		});


		// delay
		delay = SynthDef(\delay, {

   		  arg in, out, delayTime=0.3, feedbackAmount =0.5, level = -10; 
		  	var signal = In.ar(in, 2);
		  	var feedback = LocalIn.ar(2);
        	signal = DelayC.ar(signal + feedback, maxdelaytime: 4, delaytime: delayTime);

				LocalOut.ar(signal * feedbackAmount);
				Out.ar(out, signal * level.dbamp); 


		}).play(target:context.xg, args: [\in, fxBus, \out, mixerBus], addAction: \addToTail);



		// reverb
		reverb = SynthDef(\reverb, {

			 arg in, out, reverbTime=10, damp=0.1, size=3.0, diff=0.7, modDepth=0.1, modFreq=2, low=1, mid=1, high=1, lowcut=500, highcut=200;
			
			 var signal = In.ar(in, 2);       
      		 signal = JPverb.ar(signal, reverbTime, damp, size, diff, modDepth, modFreq, low, mid, high, lowcut, highcut);
			 Out.ar(out, signal);


		}).play(target:context.xg, args: [\in, reverbBus, \out, mixerBus,], addAction: \addToTail);



		// Mixer and FX
		mixer = SynthDef(\mixer, {


			 arg in, out, sidechain,  compMix = -1, compLevel = 0, thresh=0.1, slopeBelow=1, slopeAbove=0.1, clampTime=0.01, relaxTime=0.2; //, mul=1, add=0;
			 var sidechain_sig = In.ar(sidechain, 2);       
			 var signal = In.ar(in, 2);
			 
			 var wet = Compander.ar(signal * compLevel.dbamp, XFade2.ar(signal, sidechain_sig, compMix), thresh, slopeBelow, slopeAbove, clampTime, relaxTime, mul: 1, add: 0);

			
			 signal = CompanderD.ar( signal, 0.7, 1, 0.4, 0.008, 0.2);    
			 
			//signal = Compander.ar(signal, sidechain_sig, thresh, slopeBelow, slopeAbove, clampTime, relaxTime, mul: 1, add: 0);
			
			signal = tanh(XFade2.ar(signal, wet, compMix).softclip);

			//ReplaceOut.ar(out, XFade2.ar(signal, wet, compMix));

			Out.ar(out, signal);

		}).play(target:context.xg, args: [\in, mixerBus,  \sidechain, sidechainBus, \out, context.out_b], addAction: \addToTail);



		this.addCommands;
		
	}



	// Functions

	queueLoadSample {
		arg sampleId, filePath;
		var item = (
			sampleId: sampleId,
			filePath: filePath
		);

		loadQueue = loadQueue.addFirst(item);
		if(loadingSample == -1, {
			this.loadSample()
		});
	}

	killVoicesPlaying {
		arg sampleId;
		var activeVoices;

		// Kill any voices that are currently playing this sampleId
		activeVoices = voiceList.select{arg v; v.sampleId == sampleId};
		activeVoices.do({
			arg v;
			if(v.startRoutine.notNil, {
				v.startRoutine.stop;
				v.startRoutine.free;
			}, {
				v.theSynth.set(\killGate, -1);
			});
			voiceList.remove(v);
		});
	}

	clearBuffer {
		arg sampleId;

		this.killVoicesPlaying(sampleId);

		if(samples[sampleId].buffer.notNil, {
			samples[sampleId].buffer.close;
			samples[sampleId].buffer.free;
			samples[sampleId].buffer = nil;
		});

		samples[sampleId].numFrames = 0;
	}

	moveSample {
		arg fromId, toId;
		var fromSample = samples[fromId];

		if(fromId != toId, {
			this.killVoicesPlaying(fromId);
			this.killVoicesPlaying(toId);
			samples[fromId] = samples[toId];
			samples[toId] = fromSample;
		});
	}

	copySample {
		arg fromId, toFirstId, toLastId;

		for(toFirstId, toLastId, {
			arg i;
			if(fromId != i, {
				this.killVoicesPlaying(fromId);
				this.killVoicesPlaying(i);
				samples[i] = samples[fromId].deepCopy;
			});
		});
	}

	copyParams {
		arg fromId, toFirstId, toLastId;

		for(toFirstId, toLastId, {
			arg i;
			var newSample;

			if((fromId != i).and(samples[i].numFrames > 0), {
				this.killVoicesPlaying(fromId);
				this.killVoicesPlaying(i);

				// Copies all except play mode and marker positions
				newSample = samples[fromId].deepCopy;

				newSample.streaming = samples[i].streaming;
				newSample.buffer = samples[i].buffer;
				newSample.path = samples[i].path;

				newSample.channels = samples[i].channels;
				newSample.sampleRate = samples[i].sampleRate;
				newSample.numFrames = samples[i].numFrames;

				newSample.startFrame = samples[i].startFrame;
				newSample.endFrame = samples[i].endFrame;
				newSample.playMode = samples[i].playMode;
				newSample.loopStartFrame = samples[i].loopStartFrame;
				newSample.loopEndFrame = samples[i].loopEndFrame;

				samples[i] = newSample;
			});
		});
	}

	loadFailed {
		arg sampleId, message;
		if(message.notNil, {
			(sampleId.asString ++ ":" + message).postln;
		});
		scriptAddress.sendBundle(0, ['/engineSampleLoadFailed', sampleId, message]);
	}

	loadSample {
		var timeoutRoutine, item, sampleId, filePath, file, buffer, sample = ();

		if(loadQueue.notEmpty, {

			item = loadQueue.pop;
			sampleId = item.sampleId;
			filePath = item.filePath;

			loadingSample = sampleId;
			// ("Load" + sampleId + filePath).postln;

			this.clearBuffer(sampleId);

			if((sampleId < 0).or(sampleId >= samples.size), {
				("Invalid sample ID:" + sampleId + "(must be 0-" ++ (samples.size - 1) ++ ").").postln;
				this.loadSample();

			}, {

				if(filePath.compare("-") != 0, {

					file = SoundFile.openRead(filePath);
					if(file.isNil, {
						this.loadFailed(sampleId, "Could not open file");
						this.loadSample();
					}, {

						// 2 sec then timeout and move to next one
						timeoutRoutine = Routine.new({
							2.yield;
							this.loadFailed(sampleId, "Loading timed out");
							this.loadSample();
						}).play;

						sample = samples[sampleId];

						sample.channels = file.numChannels.min(2);
						sample.sampleRate = file.sampleRate;
						sample.startFrame = 0;
						sample.endFrame = file.numFrames;
						sample.loopStartFrame = 0;
						sample.loopEndFrame = file.numFrames;

						// If file is over the buffer-addressable number of frames (~5.8mins at 48kHz) then prepare it for streaming instead.
						// Streaming has fairly limited options for playback (no looping etc).

						if(file.numFrames < 16777216, {
						// if(file.duration < 10, {

							// Load into memory
							if(file.numChannels == 1, {
								buffer = Buffer.read(server: context.server, path: filePath, action: {
									arg buf;
									sample.numFrames = file.numFrames;
									scriptAddress.sendBundle(0, ['/engineSampleLoaded', sampleId, 0, file.numFrames, file.numChannels, file.sampleRate]);
									// ("Buffer" + sampleId + "loaded:" + buf.numFrames + "frames." + buf.duration.round(0.01) + "secs." + buf.numChannels + "channel.").postln;
									this.queueWaveformGeneration(sampleId, filePath);
									timeoutRoutine.stop();
									this.loadSample();
								});
							}, {
								buffer = Buffer.readChannel(server: context.server, path: filePath, channels: [0, 1], action: {
									arg buf;
									sample.numFrames = file.numFrames;
									scriptAddress.sendBundle(0, ['/engineSampleLoaded', sampleId, 0, file.numFrames, file.numChannels, file.sampleRate]);
									// ("Buffer" + sampleId + "loaded:" + buf.numFrames + "frames." + buf.duration.round(0.01) + "secs." + buf.numChannels + "channels.").postln;
									this.queueWaveformGeneration(sampleId, filePath);
									timeoutRoutine.stop();
									this.loadSample();
								});
							});
							sample.buffer = buffer;
							sample.streaming = 0;

						}, {
							if(file.numChannels > 2, {
								this.loadFailed(sampleId, "Too many chans (" ++ file.numChannels ++ ")");
								timeoutRoutine.stop();
								this.loadSample();
							}, {
								// Prepare for streaming from disk
								sample.path = filePath;
								sample.streaming = 1;
								sample.numFrames = file.numFrames;
								scriptAddress.sendBundle(0, ['/engineSampleLoaded', sampleId, 1, file.numFrames, file.numChannels, file.sampleRate]);
								// ("Stream buffer" + sampleId + "prepared:" + file.numFrames + "frames." + file.duration.round(0.01) + "secs." + file.numChannels + "channels.").postln;
								this.queueWaveformGeneration(sampleId, filePath);
								timeoutRoutine.stop();
								this.loadSample();
							});
						});

						file.close;
						samples[sampleId] = sample;

					});
				}, {
					this.loadFailed(sampleId);
					this.loadSample();
				});
			});
		}, {
			// Done
			loadingSample = -1;
		});
	}

	clearSamples {
		arg firstId, lastId = firstId;

		this.stopWaveformGeneration(firstId, lastId);

		firstId.for(lastId, {
			arg i;
			var removeQueueIndex;

			if(samples[i].notNil, {

				// Remove from load queue
				removeQueueIndex = loadQueue.detectIndex({
					arg item;
					item.sampleId == i;
				});
				if(removeQueueIndex.notNil, {
					loadQueue.removeAt(removeQueueIndex);
				});

				this.clearBuffer(i);

				samples[i] = defaultSample.deepCopy;
			});

		});
	}

	queueWaveformGeneration {
		arg sampleId, filePath;
		var item;

		this.stopWaveformGeneration(sampleId);

		if(generateWaveformsOnLoad, {

			item = (
				sampleId: sampleId,
				filePath: filePath
			);

			waveformQueue = waveformQueue.addFirst(item);

			if(generatingWaveform == -1, {
				this.generateWaveforms()
			});
		});
	}

	stopWaveformGeneration {
		arg firstId, lastId = firstId;

		// Clear from queue
		firstId.for(lastId, {
			arg i;
			var removeQueueIndex;

			// Remove any existing with same ID
			removeQueueIndex = waveformQueue.detectIndex({
				arg item;
				item.sampleId == i;
			});
			if(removeQueueIndex.notNil, {
				waveformQueue.removeAt(removeQueueIndex);
			});
		});

		// Stop currently in progress
		if((generatingWaveform >= firstId).and(generatingWaveform <= lastId), {
			abandonCurrentWaveform = true;
		});
	}

	generateWaveforms {

		var sendEvery = 24000;
		var sampleId, file, samplesArray, numFrames, numChannels, sampleRate, block, iterations, downsample;
		var min, max, offset, i, f;
		var waveform, routine;

		"Started generating waveforms".postln;

		waveformRoutine = Routine.new({

			while({ waveformQueue.notEmpty }, {
				var startSecs = Date.getDate.rawSeconds;
				var item = waveformQueue.pop;
				sampleId = item.sampleId;
				generatingWaveform = sampleId;

				file = SoundFile.openRead(item.filePath);
				if(file.isNil, {
					("File could not be opened for waveform generation:" + item.filePath).postln;
				}, {

					// Load samples into array
					numFrames = file.numFrames;
					numChannels = file.numChannels;
					sampleRate = file.sampleRate;
					samplesArray = FloatArray.newClear(numFrames * numChannels);
					file.readData(samplesArray);
					file.close;

					block = (numFrames / waveformDisplayRes).roundUp;
					iterations = waveformDisplayRes.min(numFrames);
					downsample = ((10 * (sampleRate / 48000)).min(block / 10).round).max(1);

					offset = 0;
					waveform = Int8Array.new((iterations * 2) + (iterations % 4));

					i = 0;
					while({ (i < iterations).and(abandonCurrentWaveform == false) }, {

						if(abandonCurrentWaveform == false, {

							min = 0;
							max = 0;

							f = i * block;
							while({ (f < (i * block + block).min(numFrames)).and(abandonCurrentWaveform == false) }, {
								var sample = 0;

								if(abandonCurrentWaveform == false, {

									for(0, numChannels.min(2) - 1, {
										arg c;
										sample = sample + samplesArray[f * numChannels + c];
									});
									sample = sample / numChannels;

									min = sample.min(min);
									max = sample.max(max);

									// Let other sclang work happen
									0.00004.yield;
								});
								f = f + downsample;
							});

							// 0-126, 63 is center (zero)
							min = min.linlin(-1, 0, 0, 63).round.asInt;
							max = max.linlin(0, 1, 63, 126).round.asInt;
							waveform = waveform.add(min);
							waveform = waveform.add(max);

							if(((i + 1 - offset) * block * numChannels >= sendEvery).and(abandonCurrentWaveform == false), {
								this.sendWaveform(sampleId, offset, waveform);
								offset = i + 1;
								waveform = Int8Array.new(((iterations - offset) * 2) + (iterations % 4));
							});
						});
						i = i + 1;
					});

					if(abandonCurrentWaveform, {
						abandonCurrentWaveform = false;
						("Waveform" + sampleId + "abandoned after" + (Date.getDate.rawSeconds - startSecs).round(0.001) + "s").postln;
					}, {
						if(waveform.size > 0, {
							this.sendWaveform(sampleId, offset, waveform);
						});
						("Waveform" + sampleId + "generated in" + (Date.getDate.rawSeconds - startSecs).round(0.001) + "s").postln;
					});
				});
			});

			"Finished generating waveforms".postln;
			generatingWaveform = -1;

		}).play;
	}

	sendWaveform {
		arg sampleId, offset, waveform;
		var padding = 0;

		// Pad to work around https://github.com/supercollider/supercollider/issues/2125
		while({ waveform.size % 4 > 0 }, {
			waveform = waveform.add(0);
			padding = padding + 1;
		});

		// ("Send waveform for" + sampleId + "offset" + offset + "size" + waveform.size).postln;
		scriptAddress.sendBundle(0, ['/engineWaveform', sampleId, offset, padding, waveform]);
	}

	assignVoice {
		arg voiceId, sampleId, freq, pitchBendRatio, vel;
		var voiceToRemove;

		// Remove a voice if ID matches or there are too many
		voiceToRemove = voiceList.detect{arg v; v.id == voiceId};
		if(voiceToRemove.isNil && (voiceList.size >= maxVoices), {
			voiceToRemove = voiceList.detect{arg v; v.gate == 0};
			if(voiceToRemove.isNil, {
				voiceToRemove = voiceList.last;
			});
		});

		if(voiceToRemove.notNil, {
			if(voiceToRemove.startRoutine.notNil, {
				voiceToRemove.startRoutine.stop;
				voiceToRemove.startRoutine.free;
				voiceList.remove(voiceToRemove);
				this.addVoice(voiceId, sampleId, freq, pitchBendAllRatio, vel, false);
			}, {
				voiceToRemove.theSynth.set(\killGate, 0);
				voiceList.remove(voiceToRemove);
				this.addVoice(voiceId, sampleId, freq, pitchBendAllRatio, vel, true);
			});
		}, {
			this.addVoice(voiceId, sampleId, freq, pitchBendAllRatio, vel, false);
		});
	}

	addVoice {
		arg voiceId, sampleId, freq, pitchBendRatio, vel, delayStart;
		var defName, sample = samples[sampleId], streamBuffer, delay = 0, cueSecs;

		if(delayStart, { delay = killDuration; });

		if(sample.numFrames > 0, {
			if(sample.streaming == 0, {
				if(sample.buffer.numChannels == 1, {
					defName = \monoBufferVoice;
				}, {
					defName = \stereoBufferVoice;
				});
				this.addSynth(defName, voiceId, sampleId, sample.buffer, freq, pitchBendRatio, vel, delay);

			}, {
				cueSecs = Date.getDate.rawSeconds;
				Buffer.cueSoundFile(server: context.server, path: sample.path, startFrame: sample.startFrame, numChannels: sample.channels, bufferSize: 65536, completionMessage: {
					arg streamBuffer;
					if(streamBuffer.numChannels == 1, {
						defName = \monoStreamingVoice;
					}, {
						defName = \stereoStreamingVoice;
					});
					delay = (delay - (Date.getDate.rawSeconds - cueSecs)).max(0);
					this.addSynth(defName, voiceId, sampleId, streamBuffer, freq, pitchBendRatio, vel, delay);
					0;
				});
			});
		});
	}

	addSynth {
		arg defName, voiceId, sampleId, buffer, freq, pitchBendRatio, vel, delay;
		var newVoice, sample = samples[sampleId];

		newVoice = (id: voiceId, sampleId: sampleId, gate: 1);

		// Delay adding a new synth until after killDuration if need be
		newVoice.startRoutine = Routine {
			delay.wait;

			newVoice.theSynth = Synth.new(defName: defName, args: [
				\out, mixerBus,
				
				\reverbSendBus, reverbBus,
				\reverbSend, sample.reverbSend,

				\delaySendBus, fxBus,
				\delaySend, sample.delaySend,

				\sidechainSendBus, sidechainBus,
				\sidechainSend, sample.sidechainSend,
				
				\bufnum, buffer.bufnum,

				\voiceId, voiceId,
				\sampleId, sampleId,

				\sampleRate, sample.sampleRate,
				
				\numFrames, sample.numFrames,
				\freq, freq,
				\transposeRatio, sample.transpose.midiratio,
				\detuneRatio, (sample.detuneCents / 100).midiratio,
				\pitchBendRatio, pitchBendRatio,
				\pitchBendSampleRatio, sample.pitchBendRatio,
				\gate, 1,
				\vel, vel,
				\pressure, pressureAll,
				\pressureSample, sample.pressure,

				\startFrame, sample.startFrame,
				\i_lockedStartFrame, sample.startFrame,
				\endFrame, sample.endFrame,
				\playMode, sample.playMode,
				\loopStartFrame, sample.loopStartFrame,
				\loopEndFrame, sample.loopEndFrame,

				\lfos, lfoBus,
				\lfo1Fade, sample.lfo1Fade,
				\lfo2Fade, sample.lfo2Fade,

				\freqModLfo1, sample.freqModLfo1,
				\freqModLfo2, sample.freqModLfo2,
				\freqModEnv, sample.freqModEnv,

				\ampAttack, sample.ampAttack,
				\ampDecay, sample.ampDecay,
				\ampSustain, sample.ampSustain,
				\ampRelease, sample.ampRelease,
				\modAttack, sample.modAttack,
				\modDecay, sample.modDecay,
				\modSustain, sample.modSustain,
				\modRelease, sample.modRelease,

				\downSampleTo, sample.downSampleTo,
				\bitDepth, sample.bitDepth,

				\filterFreq, sample.filterFreq,
				\filterReso, sample.filterReso,
				\filterType, sample.filterType,
				\filterTracking, sample.filterTracking,
				\filterFreqModLfo1, sample.filterFreqModLfo1,
				\filterFreqModLfo2, sample.filterFreqModLfo2,
				\filterFreqModEnv, sample.filterFreqModEnv,
				\filterFreqModVel, sample.filterFreqModVel,
				\filterFreqModPressure, sample.filterFreqModPressure,

				\pan, sample.pan,
				\panModLfo1, sample.panModLfo1,
				\panModLfo2, sample.panModLfo2,
				\panModEnv, sample.panModEnv,

				\amp, sample.amp,
				\ampModLfo1, sample.ampModLfo1,
				\ampModLfo2, sample.ampModLfo2,

			], target: voiceGroup).onFree({

				if(sample.streaming == 1, {
					if(buffer.notNil, {
						buffer.close;
						buffer.free;
					});
				});
				voiceList.remove(newVoice);

				scriptAddress.sendBundle(0, ['/engineVoiceFreed', sampleId, voiceId]);

			});

			scriptAddress.sendBundle(0, ['/enginePlayPosition', sampleId, voiceId, sample.startFrame / sample.numFrames]);

			newVoice.startRoutine.free;
			newVoice.startRoutine = nil;
		}.play;

		voiceList.addFirst(newVoice);
	}



	// Commands

	setArgOnVoice {
		arg voiceId, name, value;
		var voice = voiceList.detect{arg v; v.id == voiceId};
		if(voice.notNil, {
			voice.theSynth.set(name, value);
		});
	}

	setArgOnSample {
		arg sampleId, name, value;
		if(samples[sampleId].notNil, {
			samples[sampleId][name] = value;
			this.setArgOnVoicesPlayingSample(sampleId, name, value);
		});
	}

	setArgOnVoicesPlayingSample {
		arg sampleId, name, value;
		var voices = voiceList.select{arg v; v.sampleId == sampleId};
		voices.do({
			arg v;
			v.theSynth.set(name, value);
		});
	}

	addCommands {

		this.addCommand(\generateWaveforms, "i", {
			arg msg;
			generateWaveformsOnLoad = (msg[1] == 1);
		});

		// noteOn(id, freq, vel, sampleId)
		this.addCommand(\noteOn, "iffi", {
			arg msg;
			var id = msg[1], freq = msg[2], vel = msg[3] ?? 1, sampleId = msg[4] ?? 0,
			sample = samples[sampleId];

			// debugBuffer.zero();

			if(sample.notNil, {
				this.assignVoice(id, sampleId, freq, pitchBendAllRatio, vel);
			});
		});

		// noteOff(id)
		this.addCommand(\noteOff, "i", {
			arg msg;
			var voice = voiceList.detect{arg v; v.id == msg[1]};
			if(voice.notNil, {
				if(voice.startRoutine.notNil, {
					voice.startRoutine.stop;
					voice.startRoutine.free;
					voiceList.remove(voice);
				}, {
					voice.theSynth.set(\gate, 0);
					voice.gate = 0;
					// Move voice to end so that oldest gate-off voices are found first when stealing
					voiceList.remove(voice);
					voiceList.add(voice);
				});
			});
		});

		// noteOffAll()
		this.addCommand(\noteOffAll, "", {
			arg msg;
			voiceList.do({
				arg v;
				if(v.startRoutine.notNil, {
					v.startRoutine.stop;
					v.startRoutine.free;
					voiceList.remove(v);
				});
				v.gate = 0;
			});
			voiceGroup.set(\gate, 0);
		});

		// noteKill(id)
		this.addCommand(\noteKill, "i", {
			arg msg;
			var voice = voiceList.detect{arg v; v.id == msg[1]};
			if(voice.notNil, {
				if(voice.startRoutine.notNil, {
					voice.startRoutine.stop;
					voice.startRoutine.free;
				}, {
					voice.theSynth.set(\killGate, 0);
				});
				voiceList.remove(voice);
			});
		});

		// noteKillAll()
		this.addCommand(\noteKillAll, "", {
			arg msg;
			voiceList.do({
				arg v;
				if(v.startRoutine.notNil, {
					v.startRoutine.stop;
					v.startRoutine.free;
				});
				v.gate = 0;
			});
			voiceGroup.set(\killGate, 0);
			voiceList.clear;
		});

		// pitchBendVoice(id, ratio)
		this.addCommand(\pitchBendVoice, "if", {
			arg msg;
			this.setArgOnVoice(msg[1], \pitchBendRatio, msg[2]);
		});

		// pitchBendSample(id, ratio)
		this.addCommand(\pitchBendSample, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \pitchBendSampleRatio, msg[2]);
		});

		// pitchBendAll(ratio)
		this.addCommand(\pitchBendAll, "f", {
			arg msg;
			pitchBendAllRatio = msg[1];
			voiceGroup.set(\pitchBendRatio, pitchBendAllRatio);
		});

		// pressureVoice(id, pressure)
		this.addCommand(\pressureVoice, "if", {
			arg msg;
			this.setArgOnVoice(msg[1], \pressure, msg[2]);
		});

		// pressureSample(id, pressure)
		this.addCommand(\pressureSample, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \pressureSample, msg[2]);
		});

		// pressureAll(pressure)
		this.addCommand(\pressureAll, "f", {
			arg msg;
			pressureAll = msg[1];
			voiceGroup.set(\pressure, pressureAll);
		});

		this.addCommand(\lfo1Freq, "f", { arg msg;
			lfos.set(\lfo1Freq, msg[1]);
		});

		this.addCommand(\lfo1WaveShape, "i", { arg msg;
			lfos.set(\lfo1WaveShape, msg[1]);
		});

		this.addCommand(\lfo2Freq, "f", { arg msg;
			lfos.set(\lfo2Freq, msg[1]);
		});

		this.addCommand(\lfo2WaveShape, "i", { arg msg;
			lfos.set(\lfo2WaveShape, msg[1]);
		});
		
    // FX commands

		this.addCommand(\compLevel, "f", { arg msg;
			mixer.set(\compLevel, msg[1]);
		});

		this.addCommand(\compMix, "f", { arg msg;
			mixer.set(\compMix, msg[1]);
		});

		this.addCommand(\compThreshold, "f", { arg msg;
			mixer.set(\thresh, msg[1]);
		});

		this.addCommand(\compSlopeBelow, "f", { arg msg;
			mixer.set(\slopeBelow, msg[1]);
		});
		this.addCommand(\compSlopeAbove, "f", { arg msg;
			mixer.set(\slopeAbove, msg[1]);
		});

		this.addCommand(\compClampTime, "f", { arg msg;
			mixer.set(\clampTime, msg[1]);
		});

		this.addCommand(\compRelaxTime, "f", { arg msg;
			mixer.set(\relaxTime, msg[1]);
		});





    // Delay

		this.addCommand(\delayTime, "f", { arg msg;
			delay.set(\delayTime, msg[1]);
		});
		
		this.addCommand(\feedbackAmount, "f", { arg msg;
			delay.set(\feedbackAmount, msg[1]);
		});

		this.addCommand(\delayLevel, "f", { arg msg;
			delay.set(\level, msg[1]);
		});
    
    // Reverb
		
		this.addCommand(\reverbTime, "f", { arg msg;
			reverb.set(\reverbTime, msg[1]);
		});
		
		this.addCommand(\reverbDamp, "f", { arg msg;
			reverb.set(\damp, msg[1]);
		});
		
		this.addCommand(\reverbSize, "f", { arg msg;
			reverb.set(\size, msg[1]);
		});
		
		this.addCommand(\reverbDiff, "f", { arg msg;
			reverb.set(\diff, msg[1]);
		});

		this.addCommand(\reverbModDepth, "f", { arg msg;
			reverb.set(\modDepth, msg[1]);
		});

		this.addCommand(\reverbModFreq, "f", { arg msg;
			reverb.set(\modFreq, msg[1]);
		});
		
		this.addCommand(\reverbLow, "f", { arg msg;
			reverb.set(\low, msg[1]);
		});
		this.addCommand(\reverbMid, "f", { arg msg;
			reverb.set(\mid, msg[1]);
		});
		this.addCommand(\reverbHigh, "f", { arg msg;
			reverb.set(\high, msg[1]);
		});
		this.addCommand(\reverbLowcut, "f", { arg msg;
			reverb.set(\lowcut, msg[1]);
		});
		this.addCommand(\reverbHighcut, "f", { arg msg;
			reverb.set(\highcut, msg[1]);
		});

		// Sample commands

		// loadSample(id, filePath)
		this.addCommand(\loadSample, "is", {
			arg msg;
			this.queueLoadSample(msg[1], msg[2].asString);
		});

		this.addCommand(\clearSamples, "ii", {
			arg msg;
			this.clearSamples(msg[1], msg[2]);
		});

		this.addCommand(\moveSample, "ii", {
			arg msg;
			this.moveSample(msg[1], msg[2]);
		});

		this.addCommand(\copySample, "iii", {
			arg msg;
			this.copySample(msg[1], msg[2], msg[3]);
		});

		this.addCommand(\copyParams, "iii", {
			arg msg;
			this.copyParams(msg[1], msg[2], msg[3]);
		});

		this.addCommand(\transpose, "if", {
			arg msg;
			var sampleId = msg[1], value = msg[2];
			if(samples[sampleId].notNil, {
				samples[sampleId][\transpose] = value;
				this.setArgOnVoicesPlayingSample(sampleId, \transposeRatio, value.midiratio);
			});

			// TODO
			// debugBuffer.write('/home/we/dust/code/timber/lib/debug.wav');
		});

		this.addCommand(\detuneCents, "if", {
			arg msg;
			var sampleId = msg[1], value = msg[2];
			if(samples[sampleId].notNil, {
				samples[sampleId][\detuneCents] = value;
				this.setArgOnVoicesPlayingSample(sampleId, \detuneRatio, (value / 100).midiratio);
			});
		});

		this.addCommand(\startFrame, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \startFrame, msg[2]);
		});

		this.addCommand(\endFrame, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \endFrame, msg[2]);
		});

		this.addCommand(\playMode, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \playMode, msg[2]);
		});

		this.addCommand(\loopStartFrame, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \loopStartFrame, msg[2]);
		});

		this.addCommand(\loopEndFrame, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \loopEndFrame, msg[2]);
		});

		this.addCommand(\lfo1Fade, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \lfo1Fade, msg[2]);
		});

		this.addCommand(\lfo2Fade, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \lfo2Fade, msg[2]);
		});

		this.addCommand(\freqModLfo1, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \freqModLfo1, msg[2]);
		});

		this.addCommand(\freqModLfo2, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \freqModLfo2, msg[2]);
		});

		this.addCommand(\freqModEnv, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \freqModEnv, msg[2]);
		});

		this.addCommand(\ampAttack, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \ampAttack, msg[2]);
		});

		this.addCommand(\ampDecay, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \ampDecay, msg[2]);
		});

		this.addCommand(\ampSustain, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \ampSustain, msg[2]);
		});

		this.addCommand(\ampRelease, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \ampRelease, msg[2]);
		});

		this.addCommand(\modAttack, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \modAttack, msg[2]);
		});

		this.addCommand(\modDecay, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \modDecay, msg[2]);
		});

		this.addCommand(\modSustain, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \modSustain, msg[2]);
		});

		this.addCommand(\modRelease, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \modRelease, msg[2]);
		});

		this.addCommand(\downSampleTo, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \downSampleTo, msg[2]);
		});

		this.addCommand(\bitDepth, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \bitDepth, msg[2]);
		});

		this.addCommand(\reverbSend, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \reverbSend, msg[2]);
		});

		this.addCommand(\delaySend, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \delaySend, msg[2]);
		});

		this.addCommand(\sidechainSend, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \sidechainSend, msg[2]);
		});

		this.addCommand(\filterFreq, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \filterFreq, msg[2]);
		});

		this.addCommand(\filterReso, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \filterReso, msg[2]);
		});

		this.addCommand(\filterType, "ii", {
			arg msg;
			this.setArgOnSample(msg[1], \filterType, msg[2]);
		});

		this.addCommand(\filterTracking, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \filterTracking, msg[2]);
		});

		this.addCommand(\filterFreqModLfo1, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \filterFreqModLfo1, msg[2]);
		});

		this.addCommand(\filterFreqModLfo2, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \filterFreqModLfo2, msg[2]);
		});

		this.addCommand(\filterFreqModEnv, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \filterFreqModEnv, msg[2]);
		});

		this.addCommand(\filterFreqModVel, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \filterFreqModVel, msg[2]);
		});

		this.addCommand(\filterFreqModPressure, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \filterFreqModPressure, msg[2]);
		});

		this.addCommand(\pan, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \pan, msg[2]);
		});

		this.addCommand(\panModLfo1, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \panModLfo1, msg[2]);
		});

		this.addCommand(\panModLfo2, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \panModLfo2, msg[2]);
		});

		this.addCommand(\panModEnv, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \panModEnv, msg[2]);
		});

		this.addCommand(\amp, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \amp, msg[2]);
		});

		this.addCommand(\ampModLfo1, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \ampModLfo1, msg[2]);
		});

		this.addCommand(\ampModLfo2, "if", {
			arg msg;
			this.setArgOnSample(msg[1], \ampModLfo2, msg[2]);
		});

	}

	free {
		if(waveformRoutine.notNil, {
			waveformRoutine.stop;
			waveformRoutine.free;
		});
		samples.do({
			arg item, i;
			if(item.notNil, {
				if(item.buffer.notNil, {
					item.buffer.free;
				});
			});
		});
		// NOTE: Are these already getting freed elsewhere?
		scriptAddress.free;
		replyFunc.free;
		synthNames.free;
		voiceList.free;
		players.free;
		voiceGroup.free;
		lfos.free;
		fxBus.free;
	  reverbBus.free;
		reverb.free;
		delay.free;
		mixer.free;
	}
}
