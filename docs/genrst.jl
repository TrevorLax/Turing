using Turing

if VERSION < v"0.5.0-"
    function Markdown.rstinline(io::IO, md::Markdown.Link)
        if ismatch(r":(func|obj|ref|exc|class|const|data):`\.*", md.url)
            Markdown.rstinline(io, md.url)
        else
            Markdown.rstinline(io, "`", md.text, " <", md.url, ">`_")
        end
    end
end

function printrst(io,md)
    mdd = md.content[1]
    sigs = shift!(mdd.content)

    decl = ".. function:: "*replace(sigs.code, "\n","\n              ")
    body = Markdown.rst(mdd)
    println(io, decl)
    println(io)
    for l in split(body, "\n")
        ismatch(r"^\s*$", l) ? println(io) : println(io, "   ", l)
    end
end

to_gen = Dict(
  "replay" => [Prior, PriorArray, PriorContainer, addPrior]
)


cd(joinpath(dirname(@__FILE__),"source")) do
  for fname in keys(to_gen)
    open("$fname.rst","w") do f
      for fun in to_gen[fname]
        md = Base.doc(fun)
        if isa(md,Markdown.MD)
          isa(md.content[1].content[1],Markdown.Code) || error("Incorrect docstring format: $D")

          printrst(f,md)
        else
          warn("$D is not documented.")
        end
      end
    end
  end
end

api_str = ""
for fname in keys(to_gen)
  api_str *= "$fname\n"
end

rst = """
Welcome to Turing.jl's documentation!
=====================================

Contents
^^^^^^^^

.. toctree::
   :maxdepth: 2
   :caption: Getting Started

   installation
   usage
   demos

.. toctree::
   :maxdepth: 2
   :caption: Development Notes

   language
   compiler
   sampler
   coroutines
   tarray
   workflow

.. toctree::
   :maxdepth: 2
   :caption: APIs

   $api_str
.. toctree::
   :maxdepth: 2
   :caption: License

   license

"""

cd(joinpath(dirname(@__FILE__),"source")) do
  open("index.rst","w") do f
    println(f,rst)
  end
end
