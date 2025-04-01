package routes

import (
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/swagger"
	"github.com/mudler/LocalAI/core/config"
	"github.com/mudler/LocalAI/core/http/endpoints/localai"
	"github.com/mudler/LocalAI/core/http/middleware"
	"github.com/mudler/LocalAI/core/p2p"
	"github.com/mudler/LocalAI/core/schema"
	"github.com/mudler/LocalAI/core/services"
	"github.com/mudler/LocalAI/internal"
	"github.com/mudler/LocalAI/pkg/model"
)

func RegisterLocalAIRoutes(router *fiber.App,
	requestExtractor *middleware.RequestExtractor,
	cl *config.BackendConfigLoader,
	ml *model.ModelLoader,
	appConfig *config.ApplicationConfig,
	galleryService *services.GalleryService) {

	router.Get("/swagger/*", swagger.HandlerDefault) // default

	// LocalAI API endpoints
	if !appConfig.DisableGalleryEndpoint {
		modelGalleryEndpointService := localai.CreateModelGalleryEndpointService(appConfig.Galleries, appConfig.ModelPath, galleryService)
		router.Post("/models/apply", modelGalleryEndpointService.ApplyModelGalleryEndpoint())
		router.Post("/models/delete/:name", modelGalleryEndpointService.DeleteModelGalleryEndpoint())

		router.Get("/models/available", modelGalleryEndpointService.ListModelFromGalleryEndpoint())
		router.Get("/models/galleries", modelGalleryEndpointService.ListModelGalleriesEndpoint())
		router.Post("/models/galleries", modelGalleryEndpointService.AddModelGalleryEndpoint())
		router.Delete("/models/galleries", modelGalleryEndpointService.RemoveModelGalleryEndpoint())
		router.Get("/models/jobs/:uuid", modelGalleryEndpointService.GetOpStatusEndpoint())
		router.Get("/models/jobs", modelGalleryEndpointService.GetAllStatusEndpoint())
	}

	router.Post("/tts",
		requestExtractor.BuildFilteredFirstAvailableDefaultModel(config.BuildUsecaseFilterFn(config.FLAG_TTS)),
		requestExtractor.SetModelAndConfig(func() schema.LocalAIRequest { return new(schema.TTSRequest) }),
		localai.TTSEndpoint(cl, ml, appConfig))

	vadChain := []fiber.Handler{
		requestExtractor.BuildFilteredFirstAvailableDefaultModel(config.BuildUsecaseFilterFn(config.FLAG_VAD)),
		requestExtractor.SetModelAndConfig(func() schema.LocalAIRequest { return new(schema.VADRequest) }),
		localai.VADEndpoint(cl, ml, appConfig),
	}
	router.Post("/vad", vadChain...)
	router.Post("/v1/vad", vadChain...)

	// Stores
	router.Post("/stores/set", localai.StoresSetEndpoint(ml, appConfig))
	router.Post("/stores/delete", localai.StoresDeleteEndpoint(ml, appConfig))
	router.Post("/stores/get", localai.StoresGetEndpoint(ml, appConfig))
	router.Post("/stores/find", localai.StoresFindEndpoint(ml, appConfig))

	if !appConfig.DisableMetrics {
		router.Get("/metrics", localai.LocalAIMetricsEndpoint())
	}

	// Backend Statistics Module
	// TODO: Should these use standard middlewares? Refactor later, they are extremely simple.
	backendMonitorService := services.NewBackendMonitorService(ml, cl, appConfig) // Split out for now
	router.Get("/backend/monitor", localai.BackendMonitorEndpoint(backendMonitorService))
	router.Post("/backend/shutdown", localai.BackendShutdownEndpoint(backendMonitorService))
	// The v1/* urls are exactly the same as above - makes local e2e testing easier if they are registered.
	router.Get("/v1/backend/monitor", localai.BackendMonitorEndpoint(backendMonitorService))
	router.Post("/v1/backend/shutdown", localai.BackendShutdownEndpoint(backendMonitorService))

	// p2p
	if p2p.IsP2PEnabled() {
		router.Get("/api/p2p", localai.ShowP2PNodes(appConfig))
		router.Get("/api/p2p/token", localai.ShowP2PToken(appConfig))
	}

	router.Get("/version", func(c *fiber.Ctx) error {
		return c.JSON(struct {
			Version string `json:"version"`
		}{Version: internal.PrintableVersion()})
	})

	router.Get("/system", localai.SystemInformations(ml, appConfig))

	// misc
	router.Post("/v1/tokenize",
		requestExtractor.BuildFilteredFirstAvailableDefaultModel(config.BuildUsecaseFilterFn(config.FLAG_TOKENIZE)),
		requestExtractor.SetModelAndConfig(func() schema.LocalAIRequest { return new(schema.TokenizeRequest) }),
		localai.TokenizeEndpoint(cl, ml, appConfig))

}
