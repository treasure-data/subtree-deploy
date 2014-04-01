Gem::Specification.new do |gem|
  gem.name        = "subtree-deploy"
  gem.description = "subtree-deploy"
  gem.homepage    = "https://github.com/treasure-data/subtree-deploy"
  gem.summary     = gem.description
  gem.version     = "0.1.0"
  gem.authors     = ["Sadayuki Furuhashi"]
  gem.email       = "frsyuki@gmail.com"
  gem.license     = "Apache 2.0"
  gem.has_rdoc    = false
  gem.files       = `git ls-files`.split("\n")
  gem.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.require_paths = ['lib']

  gem.add_dependency "rake", ">= 0.9.2"
end
