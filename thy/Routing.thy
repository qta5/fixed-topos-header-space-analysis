theory Routing
imports PrefixMatch  "../topoS/interface_abstraction/Network" CaesarTheories
begin

subsection{*Definition*}

record routing_rule =
  routing_match :: prefix_match (* done on the dst *)
  routing_action :: "port set"

type_synonym prefix_routing = "routing_rule list"

definition valid_prefixes where
  "valid_prefixes r = foldr conj (map (\<lambda>rr. valid_prefix (routing_match rr)) r) True"
lemma valid_prefixes_split: "valid_prefixes (r#rs) \<Longrightarrow> valid_prefix (routing_match r) \<and> valid_prefixes rs"
  using valid_prefixes_def by force
lemma valid_prefixes_alt_def: "valid_prefixes r = (\<forall>e \<in> set r. valid_prefix (routing_match e))"
  unfolding valid_prefixes_def
  unfolding foldr_map
  unfolding comp_def
  unfolding foldr_True_set
  ..
  
fun is_longest_prefix_routing :: "prefix_routing \<Rightarrow> bool" where
  "is_longest_prefix_routing (r1#r2#rs) = ((pfxm_length (routing_match r1) \<ge> pfxm_length (routing_match r2)) \<and>
   is_longest_prefix_routing (r2#rs))" |
  "is_longest_prefix_routing _ = True"

(*example: get longest prefix match by sorting by pfxm_length*)
value "rev (sort_key (\<lambda>r. pfxm_length (routing_match r)) [
  \<lparr> routing_match = \<lparr> pfxm_prefix = 1::ipv4addr, pfxm_length = 3 \<rparr>, routing_action = {} \<rparr>,
  \<lparr> routing_match = \<lparr> pfxm_prefix = 2::ipv4addr, pfxm_length = 8 \<rparr>, routing_action = {} \<rparr>,
  \<lparr> routing_match = \<lparr> pfxm_prefix = 3::ipv4addr, pfxm_length = 4 \<rparr>, routing_action = {} \<rparr>])"
lemma longest_prefix_routing_no_sort: 
  "is_longest_prefix_routing tbl \<Longrightarrow>
  (sort_key (\<lambda>r. 32 - pfxm_length (routing_match r)) tbl) = tbl"
  by (induction tbl rule: is_longest_prefix_routing.induct) auto
 
fun has_default_route :: "prefix_routing \<Rightarrow> bool" where
"has_default_route (r#rs) = (((pfxm_length (routing_match r)) = 0) \<or> has_default_route rs)" |
"has_default_route Nil = False"

definition correct_routing :: "prefix_routing \<Rightarrow> bool" where 
  "correct_routing r \<equiv> is_longest_prefix_routing r \<and> has_default_route r \<and> valid_prefixes r"

lemma is_longest_prefix_routing_rule_exclusion1:
  assumes "is_longest_prefix_routing (r1 # rn # rss)"
  shows "is_longest_prefix_routing (r1 # rss)"
using assms  by(case_tac rss, simp_all)
  
lemma is_longest_prefix_routing_rules_injection:
  assumes "is_longest_prefix_routing r"
  assumes "r = r1 # rs @ r2 # rss"
  shows "(pfxm_length (routing_match r1) \<ge> pfxm_length (routing_match r2))"
using assms
proof(induction rs arbitrary: r)
  case (Cons rn rs)
  let ?ro = "r1 # rs @ r2 # rss"
  have "is_longest_prefix_routing ?ro" using Cons.prems is_longest_prefix_routing_rule_exclusion1[of r1 rn "rs @ r2 # rss"] by simp
  from Cons.IH[OF this] show ?case by simp
qed simp

subsection{*Single Packet Semantics*}

value "valid_prefix \<lparr>pfxm_prefix=ipv4addr_of_dotteddecimal (192,168,0,0), pfxm_length=24\<rparr> \<and> 
  prefix_match_semantics \<lparr>pfxm_prefix=ipv4addr_of_dotteddecimal (192,168,0,0), pfxm_length=24\<rparr> 
      (ipv4addr_of_dotteddecimal (192,168,0,42))"

type_synonym packet = "ipv4addr hdr"
definition "extract_addr f p \<equiv> (case f p of NetworkBox a \<Rightarrow> a | Host a \<Rightarrow> a)"
definition dst_addr :: "'v hdr \<Rightarrow> 'v" where
"dst_addr \<equiv>  extract_addr snd"
lemma dst_addr_f: "(f = Host \<or> f = NetworkBox) \<Longrightarrow> dst_addr (src, f dst) = dst"
  unfolding dst_addr_def extract_addr_def snd_def by auto

(*assumes: correct_routing*)
fun routing_table_semantics :: "prefix_routing \<Rightarrow> ipv4addr \<Rightarrow> port set" where
"routing_table_semantics [] _ = {}" | 
"routing_table_semantics (r#rs) p = (if prefix_match_semantics (routing_match r) p then routing_action r else routing_table_semantics rs p)"

definition "packet_routing_table_semantics rtbl p \<equiv> routing_table_semantics rtbl (dst_addr p)"

lemma routing_table_semantics_ports_from_table: "valid_prefixes rtbl \<Longrightarrow> has_default_route rtbl \<Longrightarrow> 
  routing_table_semantics rtbl packet = ports \<Longrightarrow> ports \<in> set (map routing_action rtbl)"
proof(induction rtbl)
  case (Cons r rs)
  note v_pfxs = valid_prefixes_split[OF Cons.prems(1)]
  show ?case
  proof(cases "pfxm_length (routing_match r) = 0")
    case True
    have "routing_action r = ports" using zero_prefix_match_all[OF conjunct1[OF v_pfxs] True] Cons.prems(3) by simp
    then show ?thesis by simp
  next
    case False
    hence "has_default_route rs" using Cons.prems(2) by simp
    from Cons.IH[OF conjunct2[OF v_pfxs] this] Cons.prems(3) show ?thesis by force
  qed
qed simp

end
