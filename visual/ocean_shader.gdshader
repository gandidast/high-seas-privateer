shader_type canvas_item;

// Pixel-Art Ocean, Island, Wind & Dynamic Weather Shader (GL Compatibility compatible)
// Samples a pre-baked deterministic SDF texture in O(1) per fragment.

uniform int world_seed = 1337420;
uniform vec2 camera_world_pos = vec2(0.0, 0.0);
uniform vec2 viewport_size = vec2(768.0, 448.0);
uniform sampler2D world_depth_tex : filter_linear, repeat_disable;
uniform float world_half_extent = 2400.0;
uniform bool has_baked_depth = false;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_strength = 1.0;

// Dynamic weather uniforms: 0 = CLEAR, 1 = FOG, 2 = STORM
uniform int weather_state = 0;
uniform float weather_intensity = 0.0;
uniform float lightning_amount = 0.0;
uniform vec2 lightning_world_pos = vec2(0.0, 0.0);

const float TAU_VAL = 6.28318530718;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// O(1) lookup of baked island signed depth field (R: [-1, 1], G: high-res [-0.24, 0.24])
float sample_signed_depth(vec2 world_pos) {
	if (!has_baked_depth) {
		return 1.0;
	}
	vec2 map_uv = world_pos / (world_half_extent * 2.0) + vec2(0.5);
	vec4 baked = texture(world_depth_tex, map_uv);
	float sd = baked.r * 2.0 - 1.0;
	if (sd > -0.22 && sd < 0.22) {
		sd = baked.g * 0.48 - 0.24;
	}
	return sd;
}

// Evaluates final depth + raw signed depth using O(1) SDF texture + sea wave
vec2 eval_depth_pair(vec2 world_pos) {
	float min_signed_depth = sample_signed_depth(world_pos);

	int seed_mod = world_seed - (world_seed / 10000) * 10000;
	float seed_f = float(seed_mod) * 0.0071;
	float sea_wave = (
		sin(world_pos.x * 0.0045 + seed_f) * cos(world_pos.y * 0.0045 - seed_f) * 0.08
		+ sin((world_pos.x + world_pos.y) * 0.009 + seed_f * 2.0) * 0.04
	);

	float depth_val;
	if (min_signed_depth > 0.22) {
		depth_val = clamp(min_signed_depth + sea_wave, 0.23, 1.0);
	} else if (min_signed_depth > 0.0) {
		float t = min_signed_depth / 0.22;
		depth_val = clamp(min_signed_depth + sea_wave * t * 0.25, 0.001, 1.0);
	} else {
		depth_val = clamp(min_signed_depth, -1.0, 0.0);
	}
	return vec2(depth_val, min_signed_depth);
}

// 4x4 Bayer matrix for crisp pixel-art dithering
float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	vec4 row = (y == 0) ? vec4(0.0, 8.0, 2.0, 10.0) :
	           (y == 1) ? vec4(12.0, 4.0, 14.0, 6.0) :
	           (y == 2) ? vec4(3.0, 11.0, 1.0, 9.0) :
	                      vec4(15.0, 7.0, 13.0, 5.0);
	float v = (x == 0) ? row.x : (x == 1) ? row.y : (x == 2) ? row.z : row.w;
	return v * 0.0625;
}

// Procedural 2D pixel-art palm tree clusters inside lush island interior
vec3 apply_palm_clusters(vec2 wp, vec3 base_col, vec2 wdir, float storm_mix) {
	float cell_size = 15.0;
	vec2 cell = floor(wp / cell_size);
	vec3 col = base_col;
	float sway_speed = mix(2.2, 5.4, storm_mix);
	float sway_amp = mix(0.75, 1.85, storm_mix);

	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 c = cell + vec2(float(ox), float(oy));
			float h = hash21(c + vec2(17.3, 41.7));
			if (h < 0.42) {
				continue;
			}
			vec2 jitter = vec2(
				floor(hash21(c + vec2(3.1, 9.4)) * 7.0) + 4.0,
				floor(hash21(c + vec2(8.2, 2.7)) * 7.0) + 4.0
			);
			vec2 tree_world = c * cell_size + jitter;
			vec2 rel = wp - tree_world;
			if (abs(rel.x) > 8.0 || rel.y < -10.0 || rel.y > 7.5) {
				continue;
			}

			float tree_depth = sample_signed_depth(tree_world);
			if (tree_depth > -0.21 || tree_depth <= -0.52) {
				continue;
			}

			// Ground shadow (+2, +3)
			vec2 shadow_rel = rel - vec2(2.0, 3.0);
			if (dot(shadow_rel, shadow_rel) <= 17.64) {
				col = mix(col, vec3(0.094, 0.239, 0.165), 0.72);
			}

			// Wind sway (quantized to 1px)
			float sway = round(sin(TIME * sway_speed + c.x * 1.7 + c.y * 2.3) * sway_amp);
			vec2 canopy_center = vec2(sway * wdir.x, -3.0 + sway * wdir.y * 0.5);

			// Short curved pixel trunk
			vec2 trunk_p = rel - vec2(0.0, -1.0);
			if (abs(trunk_p.x - sway * 0.4) <= 0.6 && rel.y <= 1.0 && rel.y >= -3.0) {
				col = vec3(0.478, 0.267, 0.176);
			}

			// 5-frond star-shaped pixel canopy
			vec2 cr = rel - canopy_center;
			float cd = length(cr);
			float ca = (cd > 0.0001) ? atan(cr.y, cr.x) : 0.0;
			float frond = cos(ca * 5.0 + h * TAU_VAL);
			float canopy_r = 3.2 + max(0.0, frond) * 2.4;

			if (cd <= canopy_r) {
				if (cd >= canopy_r - 1.0) {
					col = vec3(0.094, 0.078, 0.145);
				} else if (cr.y < -0.5 || cr.x < -0.5) {
					col = vec3(0.553, 0.878, 0.302);
				} else if (frond > 0.2) {
					col = vec3(0.325, 0.745, 0.286);
				} else {
					col = vec3(0.169, 0.447, 0.235);
				}
			}
		}
	}
	return col;
}

void fragment() {
	vec2 raw_world_pos = camera_world_pos + (UV - vec2(0.5)) * viewport_size;
	vec2 wp = floor(raw_world_pos);

	vec2 dp = eval_depth_pair(wp);
	float depth = dp.x;

	vec2 wdir = (length(wind_dir) > 0.001) ? normalize(wind_dir) : vec2(1.0, 0.0);
	vec2 wperp = vec2(-wdir.y, wdir.x);

	float w_int = clamp(weather_intensity, 0.0, 1.0);
	float fog_mix = (weather_state == 1) ? w_int : 0.0;
	float storm_mix = (weather_state == 2) ? w_int : 0.0;

	vec3 col = vec3(0.078, 0.204, 0.392);
	float dither = bayer4(wp);

	// ------------------------------------------------------------------
	// 1. LAND vs WATER CLASSIFICATION (1:1 Pixel Art)
	// ------------------------------------------------------------------
	if (depth <= 0.0) {
		bool near_coast = (depth > -0.045);
		bool near_veg = (depth > -0.225 && depth < -0.145);
		bool near_rock = (depth > -0.595 && depth < -0.515);

		float d_r = depth;
		float d_l = depth;
		float d_d = depth;
		float d_u = depth;
		if (near_coast || near_veg || near_rock) {
			d_r = sample_signed_depth(wp + vec2(1.0, 0.0));
			d_l = sample_signed_depth(wp - vec2(1.0, 0.0));
			d_d = sample_signed_depth(wp + vec2(0.0, 1.0));
			d_u = sample_signed_depth(wp - vec2(0.0, 1.0));
		}

		// Warm sandy beach: -0.18 < depth <= 0.0
		if (depth > -0.18) {
			float grain = hash21(wp * 0.5);
			col = vec3(0.910, 0.757, 0.439);
			if (depth > -0.055) {
				col = vec3(0.831, 0.627, 0.322);
			} else if (grain > 0.86) {
				col = vec3(0.957, 0.855, 0.596);
			} else if (grain < 0.10) {
				col = vec3(0.769, 0.569, 0.310);
			}

			if (d_l > 0.0 || d_u > 0.0) {
				col = vec3(0.973, 0.898, 0.690);
			}
			if (d_r > 0.0 || d_l > 0.0 || d_d > 0.0 || d_u > 0.0) {
				col = vec3(0.094, 0.078, 0.145);
			}
		}
		// Lush island green: -0.55 < depth <= -0.18
		else if (depth > -0.55) {
			float turf = hash21(floor(wp * 0.5));
			col = vec3(0.243, 0.537, 0.282);
			if (depth > -0.26) {
				col = vec3(0.388, 0.780, 0.302);
			} else if (turf > 0.78) {
				col = vec3(0.329, 0.671, 0.294);
			} else if (turf < 0.16) {
				col = vec3(0.149, 0.361, 0.259);
			}

			col = apply_palm_clusters(wp, col, wdir, storm_mix);

			if (d_r > -0.18 || d_l > -0.18 || d_d > -0.18 || d_u > -0.18) {
				col = vec3(0.118, 0.227, 0.161);
			}
		}
		// Pixel rocks & cliff peaks: depth <= -0.55
		else {
			float strata = floor((-depth - 0.55) * 18.0);
			float tex_noise = hash21(floor(wp * 0.5));
			col = vec3(0.431, 0.388, 0.478);
			if (mod(strata, 2.0) < 0.5) {
				col = vec3(0.337, 0.298, 0.392);
			}
			if (depth < -0.78) {
				col = vec3(0.604, 0.565, 0.651);
			}
			if (tex_noise > 0.85) {
				col = vec3(0.761, 0.729, 0.808);
			}

			if (d_l > -0.55 || d_u > -0.55) {
				col = vec3(0.780, 0.753, 0.812);
			}
			if (d_r > -0.55 || d_l > -0.55 || d_d > -0.55 || d_u > -0.55) {
				col = vec3(0.094, 0.078, 0.145);
			}
		}

		// Storm overcast shading on islands (keeps dark outlines intact)
		if (storm_mix > 0.01) {
			col = mix(col, col * vec3(0.66, 0.72, 0.82), storm_mix * 0.65);
		}
	}
	// ------------------------------------------------------------------
	// 2. SHALLOW TURQUOISE SHOALS WITH BAYER DITHERING (0.0 < depth < 0.22)
	// ------------------------------------------------------------------
	else if (depth < 0.22) {
		float t = depth / 0.22;

		vec3 shallow_inner = mix(vec3(0.345, 0.855, 0.788), vec3(0.216, 0.565, 0.604), storm_mix);
		vec3 shallow_mid = mix(vec3(0.196, 0.686, 0.686), vec3(0.125, 0.431, 0.514), storm_mix);
		vec3 shallow_outer = mix(vec3(0.145, 0.486, 0.620), vec3(0.086, 0.298, 0.439), storm_mix);

		if (t < 0.45 + (dither - 0.5) * 0.14) {
			col = shallow_inner;
		} else if (t < 0.78 + (dither - 0.5) * 0.16) {
			col = shallow_mid;
		} else {
			col = shallow_outer;
		}

		float caustic = sin(wp.x * 0.16 + TIME * 1.8) * cos(wp.y * 0.16 - TIME * 1.4);
		if (caustic > 0.78 && storm_mix < 0.5) {
			col = mix(col, vec3(0.659, 0.945, 0.910), 0.55 * (1.0 - storm_mix));
		}

		// Animated white 1px pixel foam rings around island coasts
		float foam_band = mix(0.085, 0.135, storm_mix);
		if (depth < foam_band) {
			float ring_speed = mix(3.4, 5.6, storm_mix);
			float ring_phase = depth * 110.0 - TIME * ring_speed;
			float wave_ring = sin(ring_phase + sin(wp.x * 0.12 + wp.y * 0.12) * 0.8);
			float edge_shore = step(depth, 0.018);
			if (edge_shore > 0.5 || wave_ring > mix(0.72, 0.48, storm_mix)) {
				col = vec3(0.957, 0.969, 0.976);
			} else if (wave_ring > mix(0.45, 0.20, storm_mix) && depth < foam_band * 0.7) {
				col = vec3(0.761, 0.953, 0.941);
			}
		}
	}
	// ------------------------------------------------------------------
	// 3. DEEP NAVIGABLE OCEAN WITH BAYER DITHERING (depth >= 0.22)
	// ------------------------------------------------------------------
	else {
		float d_norm = clamp((depth - 0.22) / 0.55, 0.0, 1.0);

		vec3 sea_light = mix(vec3(0.133, 0.412, 0.604), vec3(0.098, 0.259, 0.416), storm_mix);
		vec3 sea_mid = mix(vec3(0.098, 0.302, 0.510), vec3(0.067, 0.184, 0.325), storm_mix);
		vec3 sea_deep = mix(vec3(0.075, 0.212, 0.404), vec3(0.047, 0.125, 0.239), storm_mix);

		float swell = 0.0;
		if (storm_mix > 0.01) {
			float swell_coord = dot(wp, wdir) * 0.065 + sin(dot(wp, wperp) * 0.03) * 1.4 - TIME * 2.8;
			swell = sin(swell_coord) * 0.25 * storm_mix;
		}
		float d_eval = clamp(d_norm - swell, 0.0, 1.0);

		if (d_eval < 0.35 + (dither - 0.5) * 0.18) {
			col = sea_light;
		} else if (d_eval < 0.72 + (dither - 0.5) * 0.18) {
			col = sea_mid;
		} else {
			col = sea_deep;
		}

		// Discrete 2D pixel wavelets (short horizontal pixel crests + storm whitecaps)
		vec2 wave_grid = vec2(floor(wp.x / 18.0), floor(wp.y / 12.0));
		float wh = hash21(wave_grid + vec2(5.2, 9.7));
		float wave_thresh = mix(0.76, 0.46, storm_mix);
		if (wh > wave_thresh) {
			float drift = floor(TIME * mix(4.0, 8.5, storm_mix) + wh * 12.0);
			vec2 local_w = vec2(mod(wp.x - drift, 18.0), mod(wp.y, 12.0));
			float bob_y = 5.0 + floor(sin(TIME * mix(2.2, 4.5, storm_mix) + wh * 10.0) * 1.5);
			float half_len = mix(2.0, 4.0, storm_mix);
			if (abs(local_w.y - bob_y) < 0.6 && local_w.x >= (6.0 - half_len) && local_w.x <= (6.0 + half_len)) {
				col = mix(vec3(0.247, 0.545, 0.761), vec3(0.541, 0.753, 0.882), storm_mix);
				if (local_w.x >= 5.0 && local_w.x <= 7.0 && wh > mix(0.89, 0.68, storm_mix)) {
					col = mix(vec3(0.490, 0.776, 0.875), vec3(0.945, 0.976, 0.992), storm_mix);
				}
			}
		}
	}

	// ------------------------------------------------------------------
	// 4. ANIMATED PIXEL WIND STREAKS ON WATER (wind_dir & wind_strength)
	// ------------------------------------------------------------------
	if (depth > 0.03) {
		float w_speed = clamp(wind_strength + storm_mix * 0.6, 0.2, 2.8);
		float along = dot(wp, wdir) - TIME * (28.0 + 34.0 * w_speed);
		float across = dot(wp, wperp);

		float lane = floor(across / 22.0);
		float lane_h = hash21(vec2(lane, 91.3));
		float across_mod = mod(across, 22.0);
		float seg_len = 36.0 + floor(lane_h * 28.0);
		float along_mod = mod(along + lane_h * 90.0, seg_len);

		if (lane_h > 0.42 && abs(across_mod - (7.0 + floor(lane_h * 8.0))) < 0.65) {
			float dash_size = 5.0 + floor(w_speed * 5.0);
			if (along_mod < dash_size) {
				float fade = (along_mod < 1.5 || along_mod > dash_size - 1.5) ? 0.22 : 0.42;
				col = mix(col, vec3(0.816, 0.961, 0.953), fade * clamp(w_speed, 0.4, 1.0));
			}
		}
	}

	// ------------------------------------------------------------------
	// 5. DYNAMIC WEATHER OVERLAYS: PIXEL FOG BANKS & STORM RAIN + LIGHTNING
	// ------------------------------------------------------------------
	if (fog_mix > 0.01) {
		vec2 fog_uv1 = floor(wp * 0.5) * 0.018 + vec2(TIME * 0.045, -TIME * 0.018);
		vec2 fog_uv2 = floor(wp * 0.5) * 0.034 + vec2(-TIME * 0.025, TIME * 0.022);
		float n1 = value_noise(fog_uv1);
		float n2 = value_noise(fog_uv2);
		float fog_density = smoothstep(0.32, 0.85, n1 * 0.65 + n2 * 0.35);
		float land_attenuation = (depth <= 0.0) ? 0.50 : 1.0;
		float fog_alpha = fog_density * fog_mix * 0.42 * land_attenuation;
		vec3 fog_color = vec3(0.753, 0.855, 0.886);
		col = mix(col, fog_color, clamp(fog_alpha, 0.0, 0.42));
	}

	if (storm_mix > 0.01) {
		vec2 rain_p = wp + vec2(-TIME * 120.0, -TIME * 260.0);
		float rx = floor(rain_p.x - rain_p.y * 0.38);
		float ry = floor(rain_p.y);
		float col_hash = hash21(vec2(mod(rx, 256.0), floor(ry / 28.0)));
		float rain_thresh = mix(0.985, 0.905, storm_mix);
		if (col_hash > rain_thresh) {
			float streak_pos = mod(ry, 28.0);
			float streak_len = 5.0 + floor(col_hash * 6.0);
			if (streak_pos < streak_len) {
				col = mix(col, vec3(0.690, 0.855, 0.961), 0.55 * storm_mix);
			}
		}
	}

	if (lightning_amount > 0.01) {
		float dist_l = length(wp - lightning_world_pos);
		float local_glow = exp(-dist_l * 0.0045) * 0.45 + 0.55;
		vec3 flash_col = vec3(0.86, 0.94, 1.0);
		col = mix(col, flash_col, clamp(lightning_amount * local_glow * 0.65, 0.0, 0.85));
	}

	COLOR = vec4(col, 1.0);
}
