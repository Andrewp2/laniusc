mod common;

use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

const FIXTURE_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/raytracer_ppm");

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Settings {
    width: i32,
    height: i32,
    samples_per_pixel: i32,
}

#[derive(Clone, Copy)]
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

#[derive(Clone, Copy)]
struct Ray {
    origin: Vec3,
    direction: Vec3,
}

#[derive(Clone, Copy)]
struct Camera {
    origin: Vec3,
    lower_left_corner: Vec3,
    horizontal: Vec3,
    vertical: Vec3,
}

#[derive(Clone, Copy)]
struct Sphere {
    center: Vec3,
    radius: f32,
    albedo: Vec3,
}

#[derive(Clone, Copy)]
struct Hit {
    ok: bool,
    t: f32,
    normal: Vec3,
    albedo: Vec3,
}

#[test]
fn raytracer_fixture_oracle_matches_reference_renderer() {
    assert!(
        fixture_path("raytracer.lani").is_file(),
        "raytracer source fixture should exist"
    );

    let settings = fixture_settings();
    let expected_ppm = read_fixture("expected.ppm");
    let expected_stdout = read_fixture("expected.stdout");

    assert_eq!(reference_ppm(settings), expected_ppm);
    assert_eq!(
        expected_stdout,
        format!("{}\n", settings.width * settings.height)
    );
    assert_ppm_shape(&expected_ppm, settings);
}

#[cfg(all(unix, target_arch = "x86_64"))]
#[test]
fn raytracer_ppm_compiles_runs_and_matches_oracle() {
    use std::os::unix::fs::PermissionsExt;

    let source_path = fixture_path("raytracer.lani");
    let expected_ppm = read_fixture("expected.ppm");
    let expected_stdout = read_fixture("expected.stdout");
    let bytes = common::run_gpu_codegen_with_timeout("raytracer PPM fixture native compile", {
        let source_path = source_path.clone();
        move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(
                &source_path,
                &Path::new(env!("CARGO_MANIFEST_DIR")).join("stdlib"),
            ))
        }
    })
    .expect("raytracer fixture should eventually compile to x86_64");

    let exe = common::TempArtifact::new("laniusc_raytracer", "raytracer_ppm", None);
    exe.write_bytes(&bytes);
    let mut permissions = fs::metadata(exe.path())
        .unwrap_or_else(|err| panic!("stat raytracer executable {}: {err}", exe.path().display()))
        .permissions();
    permissions.set_mode(0o700);
    fs::set_permissions(exe.path(), permissions)
        .unwrap_or_else(|err| panic!("chmod raytracer executable {}: {err}", exe.path().display()));

    let work_dir = TempDir::new("raytracer_ppm");
    fs::copy(
        fixture_path("render_settings.txt"),
        work_dir.path().join("render_settings.txt"),
    )
    .unwrap_or_else(|err| panic!("copy raytracer settings into temp cwd: {err}"));

    let mut command = Command::new(exe.path());
    command.current_dir(work_dir.path());
    let output = common::short_process_output_with_timeout("run raytracer fixture", &mut command);
    common::assert_command_success("raytracer fixture execution", &output);

    let actual_stdout = common::stdout_utf8("raytracer fixture stdout", output.stdout);
    let actual_ppm = fs::read_to_string(work_dir.path().join("lanius_ray.ppm"))
        .unwrap_or_else(|err| panic!("read raytracer output PPM: {err}"));

    assert_eq!(actual_stdout, expected_stdout);
    assert_eq!(actual_ppm, expected_ppm);
}

#[cfg(not(all(unix, target_arch = "x86_64")))]
#[test]
#[ignore = "native x86_64 execution acceptance test"]
fn raytracer_ppm_compiles_runs_and_matches_oracle() {}

fn fixture_path(name: &str) -> PathBuf {
    Path::new(FIXTURE_DIR).join(name)
}

fn read_fixture(name: &str) -> String {
    let path = fixture_path(name);
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("read fixture {}: {err}", path.display()))
}

fn fixture_settings() -> Settings {
    let text = read_fixture("render_settings.txt");
    let values = text
        .split_whitespace()
        .map(|word| {
            word.parse::<i32>()
                .unwrap_or_else(|err| panic!("parse render setting {word:?}: {err}"))
        })
        .collect::<Vec<_>>();
    assert!(
        values.len() >= 3,
        "render_settings.txt must contain width, height, and samples_per_pixel"
    );
    sanitize_settings(Settings {
        width: values[0],
        height: values[1],
        samples_per_pixel: values[2],
    })
}

fn sanitize_settings(settings: Settings) -> Settings {
    Settings {
        width: settings.width.max(2),
        height: settings.height.max(2),
        samples_per_pixel: settings.samples_per_pixel.max(1),
    }
}

fn assert_ppm_shape(ppm: &str, settings: Settings) {
    let words = ppm.split_whitespace().collect::<Vec<_>>();
    assert!(words.len() >= 4, "PPM must include a P3 header");
    assert_eq!(words[0], "P3");
    assert_eq!(words[1].parse::<i32>().unwrap(), settings.width);
    assert_eq!(words[2].parse::<i32>().unwrap(), settings.height);
    assert_eq!(words[3].parse::<i32>().unwrap(), 255);

    let channels = &words[4..];
    assert_eq!(
        channels.len(),
        (settings.width * settings.height * 3) as usize,
        "PPM should contain one RGB triplet per pixel"
    );
    for channel in channels {
        let value = channel
            .parse::<i32>()
            .unwrap_or_else(|err| panic!("parse PPM channel {channel:?}: {err}"));
        assert!(
            (0..=255).contains(&value),
            "PPM channel out of range: {value}"
        );
    }
}

fn reference_ppm(settings: Settings) -> String {
    let camera = make_camera(settings);
    let world = make_world();
    let mut ppm = format!("P3\n{} {}\n255\n", settings.width, settings.height);

    let mut y = 0;
    while y < settings.height {
        let mut x = 0;
        while x < settings.width {
            let color = pixel_color(camera, world, settings, x, y);
            ppm.push_str(&format!(
                "{} {} {}\n",
                color_to_byte(color.x),
                color_to_byte(color.y),
                color_to_byte(color.z)
            ));
            x += 1;
        }
        y += 1;
    }

    ppm
}

fn vec3(x: f32, y: f32, z: f32) -> Vec3 {
    Vec3 { x, y, z }
}

fn add(left: Vec3, right: Vec3) -> Vec3 {
    vec3(left.x + right.x, left.y + right.y, left.z + right.z)
}

fn sub(left: Vec3, right: Vec3) -> Vec3 {
    vec3(left.x - right.x, left.y - right.y, left.z - right.z)
}

fn mul_scalar(value: Vec3, scale: f32) -> Vec3 {
    vec3(value.x * scale, value.y * scale, value.z * scale)
}

fn dot(left: Vec3, right: Vec3) -> f32 {
    left.x * right.x + left.y * right.y + left.z * right.z
}

fn sqrt_approx(value: f32) -> f32 {
    if value <= 0.0 {
        return 0.0;
    }
    let mut estimate = value;
    let mut step = 0;
    while step < 8 {
        estimate = 0.5 * (estimate + value / estimate);
        step += 1;
    }
    estimate
}

fn length(value: Vec3) -> f32 {
    sqrt_approx(dot(value, value))
}

fn unit(value: Vec3) -> Vec3 {
    let len = length(value);
    if len == 0.0 {
        value
    } else {
        mul_scalar(value, 1.0 / len)
    }
}

fn lerp(left: Vec3, right: Vec3, t: f32) -> Vec3 {
    add(mul_scalar(left, 1.0 - t), mul_scalar(right, t))
}

fn ray_at(ray: Ray, t: f32) -> Vec3 {
    add(ray.origin, mul_scalar(ray.direction, t))
}

fn miss() -> Hit {
    Hit {
        ok: false,
        t: 0.0,
        normal: vec3(0.0, 0.0, 0.0),
        albedo: vec3(0.0, 0.0, 0.0),
    }
}

fn hit_sphere(sphere: Sphere, ray: Ray, t_min: f32, t_max: f32) -> Hit {
    let oc = sub(ray.origin, sphere.center);
    let a = dot(ray.direction, ray.direction);
    let half_b = dot(oc, ray.direction);
    let c = dot(oc, oc) - sphere.radius * sphere.radius;
    let discriminant = half_b * half_b - a * c;
    if discriminant < 0.0 {
        return miss();
    }

    let sqrtd = sqrt_approx(discriminant);
    let mut root = (-half_b - sqrtd) / a;
    if root < t_min || root > t_max {
        root = (-half_b + sqrtd) / a;
        if root < t_min || root > t_max {
            return miss();
        }
    }

    let point = ray_at(ray, root);
    let outward_normal = mul_scalar(sub(point, sphere.center), 1.0 / sphere.radius);
    Hit {
        ok: true,
        t: root,
        normal: unit(outward_normal),
        albedo: sphere.albedo,
    }
}

fn hit_world(world: [Sphere; 3], ray: Ray) -> Hit {
    let mut closest_so_far = 1_000_000.0;
    let mut result = miss();
    let mut index = 0;
    while index < world.len() {
        let hit = hit_sphere(world[index], ray, 0.001, closest_so_far);
        if hit.ok {
            closest_so_far = hit.t;
            result = hit;
        }
        index += 1;
    }
    result
}

fn sky_color(ray: Ray) -> Vec3 {
    let dir = unit(ray.direction);
    let t = 0.5 * (dir.y + 1.0);
    lerp(vec3(1.0, 1.0, 1.0), vec3(0.5, 0.7, 1.0), t)
}

fn ray_color(ray: Ray, world: [Sphere; 3]) -> Vec3 {
    let hit = hit_world(world, ray);
    if hit.ok {
        let light_dir = unit(vec3(-0.4, 0.9, -0.6));
        let diffuse = dot(hit.normal, light_dir);
        let mut shade = 0.18;
        if diffuse > 0.0 {
            shade += 0.82 * diffuse;
        }
        return mul_scalar(hit.albedo, shade);
    }
    sky_color(ray)
}

fn make_camera(settings: Settings) -> Camera {
    let aspect_ratio = settings.width as f32 / settings.height as f32;
    let viewport_height = 2.0;
    let viewport_width = aspect_ratio * viewport_height;
    let focal_length = 1.0;
    let origin = vec3(0.0, 0.0, 0.0);
    let horizontal = vec3(viewport_width, 0.0, 0.0);
    let vertical = vec3(0.0, viewport_height, 0.0);
    let lower_left_corner = sub(
        sub(
            sub(origin, mul_scalar(horizontal, 0.5)),
            mul_scalar(vertical, 0.5),
        ),
        vec3(0.0, 0.0, focal_length),
    );
    Camera {
        origin,
        lower_left_corner,
        horizontal,
        vertical,
    }
}

fn camera_ray(camera: Camera, u: f32, v: f32) -> Ray {
    let across = mul_scalar(camera.horizontal, u);
    let up = mul_scalar(camera.vertical, v);
    let target = add(add(camera.lower_left_corner, across), up);
    Ray {
        origin: camera.origin,
        direction: sub(target, camera.origin),
    }
}

fn make_world() -> [Sphere; 3] {
    [
        Sphere {
            center: vec3(0.0, -100.5, -1.0),
            radius: 100.0,
            albedo: vec3(0.8, 0.8, 0.0),
        },
        Sphere {
            center: vec3(0.0, 0.0, -1.0),
            radius: 0.5,
            albedo: vec3(0.7, 0.3, 0.3),
        },
        Sphere {
            center: vec3(1.0, 0.0, -1.6),
            radius: 0.5,
            albedo: vec3(0.2, 0.4, 0.8),
        },
    ]
}

fn pixel_color(camera: Camera, world: [Sphere; 3], settings: Settings, x: i32, y: i32) -> Vec3 {
    let samples = settings.samples_per_pixel;
    let samples_f = samples as f32;
    let mut color = vec3(0.0, 0.0, 0.0);
    let mut sample_y = 0;
    while sample_y < samples {
        let mut sample_x = 0;
        while sample_x < samples {
            let x_offset = (sample_x as f32 + 0.5) / samples_f;
            let y_offset = (sample_y as f32 + 0.5) / samples_f;
            let u = (x as f32 + x_offset) / (settings.width - 1) as f32;
            let row_from_top = settings.height - 1 - y;
            let v = (row_from_top as f32 + y_offset) / (settings.height - 1) as f32;
            color = add(color, ray_color(camera_ray(camera, u, v), world));
            sample_x += 1;
        }
        sample_y += 1;
    }
    mul_scalar(color, 1.0 / (samples_f * samples_f))
}

fn clamp01(value: f32) -> f32 {
    if value < 0.0 {
        0.0
    } else if value > 0.999 {
        0.999
    } else {
        value
    }
}

fn linear_to_gamma(value: f32) -> f32 {
    sqrt_approx(clamp01(value))
}

fn color_to_byte(value: f32) -> i32 {
    let scaled = linear_to_gamma(value) * 256.0;
    let mut byte = 0;
    let mut threshold = 1.0;
    while threshold <= scaled && byte < 255 {
        byte += 1;
        threshold += 1.0;
    }
    byte
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(stem: &str) -> Self {
        let path = common::temp_artifact_path("laniusc_raytracer", stem, None);
        fs::create_dir(&path)
            .unwrap_or_else(|err| panic!("create temp directory {}: {err}", path.display()));
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        match fs::remove_dir_all(&self.path) {
            Ok(()) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => eprintln!(
                "failed to remove temp directory {}: {err}",
                self.path.display()
            ),
        }
    }
}
