# Turing.jl

[![Build Status](https://travis-ci.org/TuringLang/Turing.jl.svg?branch=master)](https://travis-ci.org/TuringLang/Turing.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/caequ1omcwndykh8/branch/master?svg=true)](https://ci.appveyor.com/project/yebai/turing-jl-pwe25/branch/master)
[![Coverage Status](https://coveralls.io/repos/github/yebai/Turing.jl/badge.svg?branch=master)](https://coveralls.io/github/yebai/Turing.jl?branch=master)
[![Turing](http://pkg.julialang.org/badges/Turing_0.5.svg)](http://pkg.julialang.org/?pkg=Turing)
[![Turing](http://pkg.julialang.org/badges/Turing_0.6.svg)](http://pkg.julialang.org/detail/Turing)
[![Gitter](https://badges.gitter.im/gitterHQ/gitter.svg)](https://gitter.im/Turing-jl/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
[![Wiki Status](https://img.shields.io/badge/wiki-v0.3-blue.svg)](https://github.com/yebai/Turing.jl/wiki)

**Turing.jl** is a Julia library for (_universal_) [probabilistic programming](https://en.wikipedia.org/wiki/Probabilistic_programming_language). Current features include:

- Universal probabilistic programming with an intuitive modelling interface
- Hamiltonian Monte Carlo (HMC) sampling for differentiable posterior distributions
- Particle MCMC sampling for complex posterior distributions involving discrete variables and stochastic control flows
- Gibbs sampling that combines particle MCMC,  HMC and many other MCMC algorithms

## News

Turing.jl is 0.6 compatible now!

## Documentation

Please visit [Turing.jl wiki](https://github.com/yebai/Turing.jl/wiki) for documentation, tutorials (e.g. [get started](https://github.com/yebai/Turing.jl/wiki/Get-started)) and other topics (e.g. [advanced usages](https://github.com/yebai/Turing.jl/wiki/Advanced-usages)). Below are some example models for Turing.

- [Introduction](https://nbviewer.jupyter.org/github/yebai/Turing.jl/blob/master/example-models/notebooks/Introduction.ipynb)
- [Gaussian Mixture Model](https://nbviewer.jupyter.org/github/yebai/Turing.jl/blob/master/example-models/notebooks/GMM.ipynb)
- [Bayesian Hidden Markov Model](https://nbviewer.jupyter.org/github/yebai/Turing.jl/blob/master/example-models/notebooks/BayesHmm.ipynb)
- [Factorical Hidden Markov Model](https://nbviewer.jupyter.org/github/yebai/Turing.jl/blob/master/example-models/notebooks/FHMM.ipynb)
- [Topic Models: LDA and MoC](https://nbviewer.jupyter.org/github/yebai/Turing.jl/blob/master/example-models/notebooks/TopicModels.ipynb)

## Contributing

Turing was originally created and is now managed by Hong Ge. Current and past Turing team members include [Hong Ge](http://mlg.eng.cam.ac.uk/hong/), [Adam Scibior](http://mlg.eng.cam.ac.uk/?portfolio=adam-scibior), [Matej Balog](http://mlg.eng.cam.ac.uk/?portfolio=matej-balog), [Zoubin Ghahramani](http://mlg.eng.cam.ac.uk/zoubin/), [Kai Xu](http://mlg.eng.cam.ac.uk/?portfolio=kai-xu), [Emma Smith](https://github.com/evsmithx), [Emile Mathieu](http://emilemathieu.fr). 
You can see the full list of on Github: https://github.com/yebai/Turing.jl/graphs/contributors. 

Turing is an open source project so if you feel you have some relevant skills and are interested in contributing then please do get in touch. See the [Contribute wiki page](https://github.com/yebai/Turing.jl/wiki/Contribute) for details on the process. You can contribute by opening issues on Github or implementing things yourself and making a pull request. We would also appreciate example models written using Turing.

## Citing Turing.jl ##

To cite Turing, please refer to the technical report. Sample BibTeX entry is given below:

```
@ARTICLE{Turing2016,
    author = {Ge, Hong and Xu, Kai and Scibior, Adam and Ghahramani, Zoubin and others},
    title = "{The Turing language for probabilistic programming.}",
    year = 2016,
    month = jun
}
```

