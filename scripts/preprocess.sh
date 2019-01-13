#!/bin/bash

. ./cmd.sh
. ./path.sh
##prepare lang

stage=1
## Given input
phone_map_txt=data/phones.60-48-39.map.txt
phone_list_txt=data/phone_list.txt
lm_text=data/lm_text.txt

## Hyperparameters
self_loop_prob=0.95
n_gram=9

. ./utils/parse_options.sh

## Output directory
dict=data/local/dict
lang=data/lang
lm_dir=data/lm/
lm=data/lm/$n_gram\gram.lm
lang_test=data/lang_test_$n_gram\gram
treedir=data/tree_sp$self_loop_prob  # it's actually just a trivial tree (no tree building)

if [ $stage -le 0 ]; then
  # Preprocess
  # Format phones.txt and get transcription
  python3 scripts/preprocess.py $phone_map_txt $phone_list_txt $trans_pkl
  
  echo "$0: Preparing dict."
  scripts/prepare_dict.sh $phone_list_txt $dict
  
  echo "$0: Generating lang directory."
  utils/prepare_lang.sh --position_dependent_phones false \
    $dict "<UNK>" data/local/lang $lang 
  echo "$0: Creating data." 
fi

if [ $stage -le 1 ]; then
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
  nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
  # Use our special topology... note that later on may have to tune this
  # topology.
  mkdir -p $treedir
  
  scripts/gen_topo.py $nonsilphonelist $silphonelist \
    --self_loop_prob $self_loop_prob > $treedir/topo
  
  ## Initiialize a tree and a transition model
  echo "$0: Initializing mono phone system."
  # feat dim does not matter here. Just set it to 10
  run.pl $treedir/log/init_mono_mdl_tree.log \
       gmm-init-mono  $treedir/topo 10 \
       $treedir/0.mdl $treedir/tree || exit 1;
  copy-transition-model $treedir/0.mdl $treedir/0.trans_mdl
  ln -s 0.mdl $treedir/final.mdl  # for consistency with scripts which require a final.mdl
fi

if [ $stage -le 2 ]; then
  echo "$0: Training phone lm and transform it to fst."
  #remove disambig symbols
  cat $lang/words.txt | awk '{print $1 }'  | grep -v "<eps>"  |\
    grep -v "#0" > $lang/vocabs.txt 
  
  mkdir -p $lm_dir

  if [ ! -f $lm ]; then
    ngram-count -text $lm_text -lm $lm -vocab $lang/vocabs.txt -limit-vocab -order $n_gram
    scripts/format_data.sh $lm $lang $lang_test
  fi

  echo "$0:Compiling graph for decoding."
  utils/mkgraph.sh \
    --self-loop-scale 1.0 $lang_test \
    $treedir $treedir/graph_$n_gram\gram  || exit 1;
fi

