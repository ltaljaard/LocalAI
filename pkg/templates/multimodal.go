package templates

import (
	"bytes"
	"text/template"

	"github.com/Masterminds/sprig/v3"
)

type MultiModalOptions struct {
	TotalImages int
	TotalAudios int
	TotalVideos int

	ImagesInMessage int
	AudiosInMessage int
	VideosInMessage int
}

type MultimodalContent struct {
	ID int
}

// https://github.com/ggml-org/llama.cpp/blob/be1d4a13db26750fac702ceb3af88ae4f39dc9f4/tools/mtmd/mtmd.h#L42
// from <__image__> to <__media__> https://github.com/ggml-org/llama.cpp/blob/79c137f77677b3c8ee3c60a7da033721b938399a/tools/mtmd/mtmd.cpp#L83
const DefaultMultiModalTemplate = "{{ range .Audio }}<__media__>{{end}}{{ range .Images }}<__media__>{{end}}{{ range .Video }}[vid-{{.ID}}]{{end}}{{.Text}}"

func TemplateMultiModal(templateString string, opts MultiModalOptions, text string) (string, error) {
	if templateString == "" {
		templateString = DefaultMultiModalTemplate
	}

	// compile the template
	tmpl, err := template.New("template").Funcs(sprig.FuncMap()).Parse(templateString)
	if err != nil {
		return "", err
	}

	videos := []MultimodalContent{}
	for i := 0; i < opts.VideosInMessage; i++ {
		videos = append(videos, MultimodalContent{ID: i + (opts.TotalVideos - opts.VideosInMessage)})
	}

	audios := []MultimodalContent{}
	for i := 0; i < opts.AudiosInMessage; i++ {
		audios = append(audios, MultimodalContent{ID: i + (opts.TotalAudios - opts.AudiosInMessage)})
	}

	images := []MultimodalContent{}
	for i := 0; i < opts.ImagesInMessage; i++ {
		images = append(images, MultimodalContent{ID: i + (opts.TotalImages - opts.ImagesInMessage)})
	}

	result := bytes.NewBuffer(nil)
	// execute the template
	err = tmpl.Execute(result, struct {
		Audio  []MultimodalContent
		Images []MultimodalContent
		Video  []MultimodalContent
		Text   string
	}{
		Audio:  audios,
		Images: images,
		Video:  videos,
		Text:   text,
	})
	return result.String(), err
}
