
////////////////////////////////////////////////////////////////////////////////////
// Arbor Vitae
////////////////////////////////////////////////////////////////////////////////////
(

s.reboot {
	s.options.numBuffers = 1024 * 256; // increase this if you need to load more samples
	s.options.memSize = 8192 * 256; // increase this if you get "alloc failed" messages
	s.options.numWireBufs = 64*64; // increase this if you get "exceeded number of interconnect buffers" messages
	s.options.maxNodes = 1024 * 256; // increase this if you are getting drop outs and the message "too many nodes"
	//s.options.numOutputBusChannels = 2; // set this to your hardware output channel size, if necessary
	//s.options.numInputBusChannels = 2; // set this to your hardware output channel size, if necessary
	//s.options.maxLogins = 8;
	s.latency = 0.2; // boot the server
	s.waitForBoot {

		s.sync;

		(
			// test SynthDef
			SynthDef(\test, { | out, freq = 440, amp = 0.1, pan = 0, gate = 1 ,rel = 1.0|
				//var audio = Blip.ar(freq,10,amp);
				var audio = SinOsc.ar(freq,0,amp);
				var env = EnvGen.ar(Env.sine(rel,amp),gate,doneAction:2);
				//var env = Linen.kr(gate,0.25,amp,rel,doneAction: Done.freeSelf);
				OffsetOut.ar(out, Pan2.ar(audio, pan, env));
			}).add;
		);

		s.sync;

		////////////////////////////////////////////////////////////////////////////////////
		// roots & branches
		////////////////////////////////////////////////////////////////////////////////////
		(
			~begin = {

				~total_duration = 780;
				// ~total_duration = 200;

				// ~debug = nil;
				~debug=true;
				~plot = true;
				~root_freq = 58.27;

				~buffer_start = List();
				~buffer_pitch = List();
				~buffer_pitch_hz = List();
				~buffer_dur = List();

				~init = {
					// kernel
					~k = [3,5,7,11];

					// 1st diag (root)
					~diag1 = [1];
					// 2nd diag (roots)
					~diag2 = ~diag1*~k;
					// 3rd diag (roots)
					~diag3 = ~diag2.collect{|i| i * ~k}.flatten.as(Set).as(Array).sort;
					// 4th diagonal (roots)
					~diag4 = ~diag3.collect{|i| i * ~k}.flatten.as(Set).as(Array).sort;

					//all diagonals
					~diags_raw = [ ~diag1 , ~diag2 , ~diag3 , ~diag4];
					~mult_raw = ~diag1 ++ ~diag2;

					////////////////////////////////////////////////////////////////////////////////////
					// definition of root and diagonal as Event
					////////////////////////////////////////////////////////////////////////////////////
					~new_root = {|rt,rtpsum|
						var root;
						root = ();
						root.rt = rt;
						root.rtprob = 1/sqrt(rt);
						root.rtpsum = rtpsum;
						root
					};
					~new_diag = {|roots,dpsum|
						var diag;
						diag = ();
						diag.roots = roots;
						diag.dpsum = dpsum;
						diag
					};
					~new_mult = {|mt,multpsum|
						var multp;
						multp = ();
						multp.mt = mt;
						multp.multprob = 1/sqrt(mt);
						multp.multpsum = multpsum;
						multp
					};
					~new_brach = {|br|
						var branch;
						branch = ();
						branch.br = br;
						branch.stbr = 0;
						branch
					};

					~init_rtpsum = {|d,rt| (1/sqrt(d[0..d.indexOf(rt)])).sum };

					~init_dpsum = {|d| (1/sqrt(d)).sum };

					// rtprob
					~recalculate_root_prob = {|root|
						root.rtprob = case
						{ root.rtprob == 0                    }{ 1/pow(root.rt,1/4); }
						{ root.rtprob == (1/pow(root.rt,1/4)) }{ 1/pow(root.rt,1/3); }
						{ root.rtprob == (1/pow(root.rt,1/3)) }{ 1/sqrt(root.rt);    }
						{ root.rtprob };
						root
					};

					// rtprob
					~recalculate_mult_prob = {|mult|
						mult.multprob = case
						{ mult.multprob == 0                    }{ 1/pow(mult.mt,1/4); }
						{ mult.multprob == (1/pow(mult.mt,1/4)) }{ 1/sqrt(mult.mt); }
						{ mult.multprob };
						mult
					};

					//create all roots
					~roots = ~diags_raw.collect({|d| d.collect({|r| ~new_root.(r,~init_rtpsum.(d,r)); }) });
					//create all diagonals
					~diagonals = ~diags_raw.collect({|d| ~new_diag.(d, ~init_dpsum.(d)) });
					//create all mults
					~mults = ~mult_raw.collect({|m,i| ~new_mult.(m, (1/sqrt(~mult_raw[0..i])).sum; ) });


					if(~debug != nil)
					{
						"INIT".postln;
					};
				};

				////////////////////////////////////////////////////////////////////////////////////
				// calculate (choose_root)
				////////////////////////////////////////////////////////////////////////////////////


				~choose_root = {

					~rdiag = {|time|
						time = case
						{ time <  100 }{ 3 }
						{ time <  260 }{ 2 }
						{ time >= 260 }{ 1 }
						{ "error".postln; };
					}.(~strt);

					// rand € R and 0 <= rand <= dpsum
					//~rand = 0.84276;
					~rand =  rrand(0,~diagonals[~rdiag-1].dpsum);

					// The chosen root (crt) is the rt on the current diagonal (rdiag) with the next greatest rtpsum in relation to rand.
					~crt = ~roots[~rdiag-1]
					.sort({|a,b| a.rtpsum < b.rtpsum})
					.select({|r| r.rtpsum > ~rand})
					.first;

					// if we are in the first diagonal there is only one root possible
					if(~crt == nil && ~rdiag == 1){
						~crt = ~roots[~rdiag-1].first;
					};

					// After every crt is determined, the rtprobs of all roots on the current rdiag (except for the root equal to crt) are recalculated
					~roots[~rdiag-1]
					.select({|r| r != ~crt})
					.do({|r| ~recalculate_root_prob.(r) });

					// Then, rtprob of the root equal to crt is set to 0
					~crt.rtprob = 0;

					// all the rtpsums and the dpsum of that diagonal need to be recalculated:
					// rtpsums
					~roots[~rdiag-1].do({|r|
						r.rtpsum = ~roots[~rdiag-1]
						.sort({|a,b| a.rt < b.rt})[0..~diags_raw[~rdiag-1].indexOf(r.rt)]
						.sum({|i| i.rtprob; });
					});

					// dpsum
					~diagonals[~rdiag-1].dpsum = ~roots[~rdiag-1].sum({|r| r.rtprob});


					if(~debug != nil)
					{
						" ////////////// CHOOSE ROOT( root: % , time: %, ROOTRDIAG: % )".format(~crt.rt,~strt,  (~roots[~rdiag-1]) ).postln;
					};
				};


				////////////////////////////////////////////////////////////////////////////////////
				// calculate (root_duration)
				////////////////////////////////////////////////////////////////////////////////////
				//The duration of a chosen root (rdur) is the amount of time during which branches are calculated from that root.
				~calculate_root_duration = {

					~exrmax = {|time|
						time = case
						{ time <  160 }{ 5    - (0.5  * ( time         / 160)) }
						{ time <  260 }{ 4.5  + (0.25 * (( time - 160) / 100)) }
						{ time <  340 }{ 4.75 - (0.5  * (( time - 260) / 80 )) }
						{ time <  420 }{ 4.25 + (0.25 * (( time - 340) / 80 )) }
						{ time <  480 }{ 4.5  - (0.5  * (( time - 420) / 60 )) }
						{ time <  600 }{ 4                                   }
						{ time >= 600 }{ 4    +        (( time - 600) / 180) }
						{ "error exrmax".postln };
					}.(~strt);

					// exrmin is always exrmax–1
					~exrmin = ~exrmax -1;

					// rand € R and exrmin <= rand <= exrmax then rdur = 2ˆrand
					~rdur = pow(2,rrand(~exrmin,~exrmax));

					// if(~debug != nil)
					// {
					// 	"CALCULATE ROOT DUR( rdur: % , exrmin: % , exrmax: % , root: % , time: % )".format(
					// 		~rdur,
					// 		~exrmin,
					// 		~exrmax,
					// 		~crt.rt,
					// 		~strt
					// 	).postln;
					// };
				};


				////////////////////////////////////////////////////////////////////////////////////
				// calculating branches
				////////////////////////////////////////////////////////////////////////////////////
				~calculate_root_branches = {

					~nmult = {|time|
						time = case
						{ time <   100 }{ 1 }
						{ time <   260 }{ 2 }
						{ time >=  260 }{ 3 }
						{ "error mult".postln };
					}.(~strt);

					~canReqB = {|time|
						time = case
						{ time <   60  }{ 1 }
						{ time <   100 }{ 0 }
						{ time <   160 }{ 1 }
						{ time <   260 }{ 0 }
						{ time <   420 }{ 1 }
						{ time >=  420 }{ 0 }
						{ "error canReqB".postln };
					}.(~strt);

					// bdiagset is constructed of all diagonals from rdiag + canReqB to rdiag + nmult.
					~bdiagset_size = (((~rdiag + ~nmult) - ~rdiag) + 1 - ~canReqB);
					~bdiagset = Array.fill(~bdiagset_size,{|i| (~rdiag + ~canReqB + i) });

					// Then, the sum of all multprobs (msetpsum) is calculated. msetpsum is equal to the multpsum of the largest multiplier, 11
					~msetpsum = ~mults.last.multpsum;
					("~msetpsum"++ 	~msetpsum).postln;

					// create new branch
					~br = ~new_brach.(~crt.rt);

					////////////////////////////////////////////////////////////////////////////////////
					// The calculation of a branch
					////////////////////////////////////////////////////////////////////////////////////
					~nmult.do({|i|
						if(i == 0){
							// first multiplication
							// rand_br € R and canReqB <= rand  <=􏰁 msetpsum
							~rand_br = rrand(~canReqB,~msetpsum);
						}{
							// successive multiplications
							// rand_n € R and 0 <= rand  <=􏰁 msetpsum
							~rand_br = rrand(0,~msetpsum);
						};

						// choose mult
						// The chosen multiplier (cmult) equals the mult with the next greatest multpsum in relation to rand
						~cmult = ~mults
						.sort({|a,b| a.multpsum < b.multpsum })
						.select({|m| m.multpsum > ~rand_br })
						.first;
						("cmult"++	~cmult).postln;

						~br.br = ~br.br * ~cmult.mt;

						 ("br"++	~br.br).postln;
					});

					// A. Once a branch is chosen, multiplier probabilities are recalculated
					~mults.do({|m| ~recalculate_mult_prob.(m) });

					// B. Then, the multprob of the multiplier equal to cmult is set to 0
					~cmult.multprob = 0;

					// All the multpsums and the msetpsum are recalculated
					~mults.do({|m|
						m.multpsum = ~mults
						.sort({|a,b| a.mt < b.mt })[0..~mult_raw.indexOf(m.mt)]
						.sum({|i| i.multprob });
					});

					~msetpsum = ~mults.sum({|i| i.multprob });

					////////////////////////////////////////////////////////////////////////////////////
					// duration of a branch
					////////////////////////////////////////////////////////////////////////////////////

					//(exbmax) is always equal to exrmax – 2.5
					~exbmax = ~exrmax - 2.5;
					// The minimum branch duration exponent (exbmin) is always exbmax – 1.
					~exbmin = ~exbmax - 1;

					// rand € R and exbmin <=􏰁 rand <=􏰁 exbmax then bdur = 2ˆrand/2
					~bdur = pow(2,rrand(~exbmin,~exbmax))/2;

					////////////////////////////////////////////////////////////////////////////////////
					// Deriving Pitches from Branches
					////////////////////////////////////////////////////////////////////////////////////
					~low = {|time|
						time = case
						{ time <  40  }{ 7800 - (1200 * (time / 40))         }
						{ time <  100 }{ 6600                                }
						{ time <  160 }{ 6600 - (1800 * ((time - 100) / 60)) }
						{ time <  260 }{ 4800                                }
						{ time <  340 }{ 4800 - (2400 * ((time - 260) / 80)) }
						{ time <  420 }{ 2400                                }
						{ time <  480 }{ 2400 - (1800 * ((time - 420) / 60)) }
						{ time <  600 }{ 600                                 }
						{ time <= 780 }{ 600 + (5400 * ((time - 600) / 180)) }
						{ ~low };
					}.(~stbr);

					~high = {|time|
						time = case
						{ time <  420 }{ 7800                                  }
						{ time <  600 }{ 7800 - (5400 * ((time - 420) / 180))  }
						{ time <= 780 }{ 2400 + (5400 * ((time - 600) / 180))  }
						{ ~high };
					}.(~stbr);

					// lcp (in cents from the fundamental) = 1200 cents in one octave
					~lcp = ((log2(~br.br)*1200).mod(1200)).round;


					// a set of integer multipliers (imultset) is determined such that, when
					// multiplied by 1200 and added to lpc, is a pitch between the low and high values
					~max_imul_size = 10;  // starting from an empiric nber of multiplier written down by andrea
					~imultset = List(~max_imul_size);
					(1..~max_imul_size).do({|i|
						~pitch = (i*1200+~lcp);
						if( (~low <= ~pitch) && (~pitch <= ~high) ) {~imultset.add(i);}
					});

					if(~imultset.size > 0){
						// pick a random mutiplier
						~pitch = (~imultset.choose * 1200) + ~lcp;
					}{
						//if no multiplier is found clamp the pitch between low and high
						if(~low == ~high){
							~pitch = ~low;
						};
						if(~pitch > ~high){
							  ~pitch = ~high; //rrand(~low,~high); //  <<< IF TOO MUCH REPETITION JUST RUN THIS
							// rrand(~low,~high);
						};
						if(~pitch < ~low){
							 ~pitch = ~low; //rrand(~low,~high);
							// rrand(~low,~high);
						};
					};

					if(~debug != nil)
					{
						"CALCULATE BRANCHES( pitch: %¢ , lcp %,  low: % , high: % , bdur: % ,  nmult: % , canReqB: % , rdiag: % , bdiagset: % , root: % , time: % )".format(
							~pitch,
							~lcp,
							~low,
							~high,
							~bdur,
							~nmult,
							~canReqB,
							~rdiag,
							~bdiagset,
							~crt.rt,
						~strt).postln;

						// plot 6 state for debug
						~changes = {|time|
							time = case
							{ time <  60  }{ "% - % % t %".format(1,~rdiag,~bdiagset,time).postln;}
							{ time <  100 }{ "% - % % t %".format(2,~rdiag,~bdiagset,time).postln;}
							{ time <  160 }{ "% - % % t %".format(3,~rdiag,~bdiagset,time).postln;}
							{ time <  260 }{ "% - % % t %".format(4,~rdiag,~bdiagset,time).postln;}
							{ time <  420 }{ "% - % % t %".format(5,~rdiag,~bdiagset,time).postln;}
							{ time >= 420 }{ "% - % % t %".format(6,~rdiag,~bdiagset,time).postln;}
							{ ~changes };
						}.(~stbr);
					};

					// convert pitch from cents to hz
					//~hz_pitch = pow(2,(~pitch/1200));
					~hz_pitch = ~root_freq* pow(2,(~pitch/1200));


					////////////////////////////////////////////////////////////////////////////////////
					// dynamics
					////////////////////////////////////////////////////////////////////////////////////

/*0 - 480 --> line from pp to f
480- 600 --> plateau f
600 - 780 --> line from f to pp */

					// ~amp = {|time|
					// 	time = case
					// 	{ time <  480 }{ 3 }
					// 	{ time <  600 }{ 2 }
					// 	{ time >= 780 }{ 1 }
					// 	{ "error".postln; };
					// }.(~strt);


					////////////////////////////////////////////////////////////////////////////////////
					// save output lists
					////////////////////////////////////////////////////////////////////////////////////
					~buffer_start.add(~stbr);

					~buffer_pitch.add(~pitch);

					~buffer_pitch_hz.add(~hz_pitch);

					~buffer_dur.add(~bdur);
				};

			};


			~run = {
				{
					////////////////////////////////////////////////////////////////////////////////////
					// generate Arbor Vitae
					////////////////////////////////////////////////////////////////////////////////////
					~exrmin = ~exbmin  = ~exrmax = ~exbmax = ~strt = ~stbr = ~rdur = ~bdur = 0;

					~init.();

					while({~strt < ~total_duration},{

						~choose_root.();

						~calculate_root_duration.();

						while({~stbr < (~strt + ~rdur)},{

							~calculate_root_branches.();

							~stbr = ~stbr + ~bdur;
						});

						~strt = ~strt + ~rdur;
					});

					// debug graphs
					if(~plot != nil)
					{
						// plot bdur graph
						Env.new(~buffer_dur.asArray,~buffer_dur.asArray).plot;

						// plot pitch and duration graph
						Env.new(~buffer_pitch.asArray,~buffer_dur.asArray).plot;

						// plot start and duration graph
						Env.new(~buffer_start.asArray,~buffer_dur.asArray).plot;
					};

					////////////////////////////////////////////////////////////////////////////////////
					// Assigning Tones to Instruments and Temporal Density
					////////////////////////////////////////////////////////////////////////////////////

					//new pattern
					(
						p = Pbind(
							\instrument, \test,
							\server, s,
							\dur, Pseq(~buffer_dur.asArray, 1),
							\rel, Pseq((~buffer_dur.asArray)*3, 1),
							\freq, Pseq(~buffer_pitch_hz.asArray, 1),
							\cents, Pseq(~buffer_pitch.asArray, 1),
						);
					);


				}.fork(AppClock);
			};
		)
	}
}
)


////////////////////////////////////////////////////////////////////////////////////
// Run algorithm
////////////////////////////////////////////////////////////////////////////////////

~begin.();
~run.();

////////////////////////////////////////////////////////////////////////////////////
// Pattern
////////////////////////////////////////////////////////////////////////////////////

//play pattern for debug
p.trace.play;
//Ptrace(p, \freq).play;

// rendering a pattern to sound file directly: does it work?
//p.render(Platform.defaultTempDir +/+ "Arbor_Vitae.aif", ~total_duration, options:s.options);

////////////////////////////////////////////////////////////////////////////////////
// Score
////////////////////////////////////////////////////////////////////////////////////

//make a score from the pattern, 780 seconds long
//z = p.asScore(~total_duration);

//save score to file
//for some reason 'asCompileString' doesn't save correctly
//f = File(Platform.defaultTempDir +/+ "Arbor_Vitae_score","w");
//f.write(z.asCompileString);
//f.close;

//load score from file
//z = Score.newFromFile(Platform.defaultTempDir +/+ "Arbor_Vitae_score");

//print score
//z.score.postcs;

//play score
//z.play(s);


(
//debug buffers output
~buffer_start.asArray.plot;
~buffer_pitch.asArray.plot;
~buffer_pitch_hz.asArray.plot;
~buffer_dur.asArray.plot;
)



//midi note to freq
//~f1 = 69.midicps;
~cent = 7800;
~f1 = 58.27;
~f2 = ~f1* pow(2,(~cent/1200));
//~f2 = 70.midicps;
//~cent = 1200 * log2(~f2/~f1)
//~hz = 440* pow(2,(~cent/1200));


/// TO DO
// amplitude variations

0 - 480 --> line from pp to f
480- 600 --> plateau f
600 - 780 --> line from f to pp

// assigned to difft 'instrmts'
//
